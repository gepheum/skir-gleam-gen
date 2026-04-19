import decode_utils
import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/string_tree.{type StringTree}
import serializer
import type_descriptor
import skir_client/internal/unrecognized

// =============================================================================
// VariantAdapter
// =============================================================================

/// A type-erased adapter for a single enum variant, used by `new_serializer`.
///
/// Build one with `constant_variant` or `wrapper_variant`.
pub type VariantAdapter(e) {
  VariantAdapter(
    name: String,
    number: Int,
    doc: String,
    /// For constant variants: `Some(value)`. For wrapper variants: `None`.
    constant: Option(e),
    /// Appends the full JSON representation of this variant.
    /// The given enum value MUST be this variant.
    append_json: fn(e, StringTree, String) -> StringTree,
    /// For wrapper variants: decodes the payload JSON into `e`.
    /// For constant variants: returns `Ok(instance)` unconditionally.
    wrap_from_json: fn(dynamic.Dynamic) -> Result(e, String),
    /// For wrapper variants: encodes the payload onto the tree.
    /// For constant variants: returns the tree unchanged.
    encode_payload: fn(e, BytesTree) -> BytesTree,
    /// For wrapper variants: decodes the payload from binary (header already consumed).
    /// For constant variants: returns `Ok(#(instance, bits))` unconditionally.
    wrap_decode: fn(BitArray, Bool) -> Result(#(e, BitArray), String),
    /// For wrapper variants: returns `Some(default_value)` via the inner
    /// serializer's zero default (used when a wrapper number appears in a
    /// constant-only context).
    /// For constant variants: returns `None`.
    wrap_default: fn() -> Option(e),
    /// For wrapper variants: returns `Some(TypeDescriptor)` for the inner type.
    /// For constant variants: returns `None`.
    type_descriptor: fn() -> Option(type_descriptor.TypeDescriptor),
  )
}

// =============================================================================
// constant_variant / wrapper_variant constructors
// =============================================================================

/// Creates a `VariantAdapter` for a constant (payload-less) enum variant.
pub fn constant_variant(
  name name: String,
  number number: Int,
  doc doc: String,
  instance instance: e,
) -> VariantAdapter(e) {
  VariantAdapter(
    name:,
    number:,
    doc:,
    constant: Some(instance),
    append_json: fn(_e, tree, eol_indent) {
      case eol_indent {
        "" -> string_tree.append(tree, int.to_string(number))
        _ -> string_tree.append(tree, json.to_string(json.string(name)))
      }
    },
    wrap_from_json: fn(_d) { Ok(instance) },
    encode_payload: fn(_e, tree) { tree },
    wrap_decode: fn(bits, _keep) { Ok(#(instance, bits)) },
    wrap_default: fn() { None },
    type_descriptor: fn() { None },
  )
}

/// Creates a `VariantAdapter` for a wrapper (payload-carrying) enum variant.
///
/// The optional `type_sig` parameter is used for recursive variant types to
/// avoid infinite recursion when computing the type descriptor. When provided,
/// the type descriptor for this variant returns `Some(TypeDescriptor(type_sig,
/// {}))` directly instead of calling `serializer_fn().adapter.type_descriptor()`.
pub fn wrapper_variant(
  name name: String,
  number number: Int,
  doc doc: String,
  serializer serializer_fn: fn() -> serializer.Serializer(v),
  type_sig type_sig: Option(type_descriptor.TypeSignature),
  wrap wrap: fn(v) -> e,
  unwrap unwrap: fn(e) -> v,
) -> VariantAdapter(e) {
  VariantAdapter(
    name:,
    number:,
    doc:,
    constant: None,
    append_json: fn(e, tree, eol_indent) {
      let ta = serializer_fn().adapter
      let v = unwrap(e)
      case eol_indent {
        "" -> {
          let t1 = string_tree.append(tree, "[" <> int.to_string(number) <> ",")
          let t2 = ta.append_json(v, t1, "")
          string_tree.append(t2, "]")
        }
        _ -> {
          let child = eol_indent <> "  "
          let t1 =
            string_tree.append(
              tree,
              "{"
                <> child
                <> json.to_string(json.string("kind"))
                <> ": "
                <> json.to_string(json.string(name))
                <> ","
                <> child
                <> json.to_string(json.string("value"))
                <> ": ",
            )
          let t2 = ta.append_json(v, t1, child)
          string_tree.append(string_tree.append(t2, eol_indent), "}")
        }
      }
    },
    wrap_from_json: fn(d) {
      let ta = serializer_fn().adapter
      case decode.run(d, ta.decode_json(False)) {
        Ok(v) -> Ok(wrap(v))
        Error([decode.DecodeError(expected:, found:, ..), ..]) ->
          Error("expected " <> expected <> " but found " <> found)
        Error([]) -> Error("decode error")
      }
    },
    encode_payload: fn(e, tree) {
      let ta = serializer_fn().adapter
      ta.encode(unwrap(e), tree)
    },
    wrap_decode: fn(bits, keep) {
      let ta = serializer_fn().adapter
      case ta.decode(bits, keep) {
        Ok(#(v, rest)) -> Ok(#(wrap(v), rest))
        Error(e) -> Error(e)
      }
    },
    wrap_default: fn() {
      let ta = serializer_fn().adapter
      case ta.decode(<<0>>, False) {
        Ok(#(v, _)) -> Some(wrap(v))
        Error(_) -> None
      }
    },
    type_descriptor: fn() {
      case type_sig {
        None -> Some(serializer_fn().adapter.type_descriptor())
        Some(sig) ->
          Some(type_descriptor.TypeDescriptor(
            type_sig: sig,
            records: dict.new(),
          ))
      }
    },
  )
}

// =============================================================================
// new_serializer
// =============================================================================

/// Builds a `Serializer` for a Skir enum type.
///
/// For use only by code generated by the Skir Gleam code generator.
///
/// Parameters:
/// - `variants`: variant adapters in declaration order (kind ordinal 1..N).
///   Must NOT include the implicit Unknown variant (ordinal 0).
/// - `get_kind_ordinal`: maps an enum value to its kind ordinal: 0 for the
///   Unknown variant, 1 for the first declared variant, and so on.
/// - `wrap_unrecognized`: wraps an `UnrecognizedVariant(e)` into the Unknown
///   constructor.
/// - `get_unrecognized`: extracts the `UnrecognizedVariant(e)` from the
///   Unknown constructor; returns `None` for any other constructor.
pub fn new_serializer(
  name name: String,
  qualified_name qualified_name: String,
  module_path module_path: String,
  doc doc: String,
  variants variants: List(VariantAdapter(e)),
  unknown_default unknown_default: e,
  get_kind_ordinal get_kind_ordinal: fn(e) -> Int,
  wrap_unrecognized wrap_unrecognized: fn(unrecognized.UnrecognizedVariant(e)) ->
    e,
  get_unrecognized get_unrecognized: fn(e) ->
    unrecognized.UnrecognizedVariant(e),
  removed_numbers removed_numbers: List(Int),
) -> serializer.Serializer(e) {
  let variants_by_number =
    list.fold(variants, dict.new(), fn(acc, v) { dict.insert(acc, v.number, v) })
  let variants_by_name =
    list.fold(variants, dict.new(), fn(acc, v) { dict.insert(acc, v.name, v) })
  serializer.make_serializer(
    serializer.make_type_adapter(
      is_default: fn(e) {
        case get_kind_ordinal(e) {
          0 ->
            case get_unrecognized(e) {
              None -> True
              Some(_) -> False
            }
          _ -> False
        }
      },
      append_json: fn(e, tree, eol_indent) {
        enum_append_json(
          variants,
          get_kind_ordinal,
          get_unrecognized,
          e,
          tree,
          eol_indent,
        )
      },
      decode_json: fn(keep) {
        decode.dynamic
        |> decode.then(fn(d) {
          case
            enum_decode_json(
              variants_by_number,
              variants_by_name,
              removed_numbers,
              unknown_default,
              wrap_unrecognized,
              d,
              keep,
            )
          {
            Ok(e) -> decode.success(e)
            Error(msg) -> decode.failure(unknown_default, msg)
          }
        })
      },
      encode: fn(e, tree) {
        enum_encode(variants, get_kind_ordinal, get_unrecognized, e, tree)
      },
      decode: fn(bits, keep) {
        enum_decode_binary(
          variants_by_number,
          removed_numbers,
          unknown_default,
          wrap_unrecognized,
          bits,
          keep,
        )
      },
      type_descriptor: fn() {
        enum_type_descriptor(
          name,
          qualified_name,
          module_path,
          doc,
          variants,
          removed_numbers,
        )
      },
    ),
  )
}

// =============================================================================
// JSON encoding
// =============================================================================

fn enum_append_json(
  variants: List(VariantAdapter(e)),
  get_kind_ordinal: fn(e) -> Int,
  get_unrecognized: fn(e) -> unrecognized.UnrecognizedVariant(e),
  e: e,
  tree: StringTree,
  eol_indent: String,
) -> StringTree {
  case get_kind_ordinal(e) {
    0 -> unknown_to_json(get_unrecognized(e), tree, eol_indent)
    ko ->
      case list.drop(variants, ko - 1) |> list.first {
        Error(_) -> string_tree.append(tree, "0")
        Ok(v) -> v.append_json(e, tree, eol_indent)
      }
  }
}

fn unknown_to_json(
  unrec: unrecognized.UnrecognizedVariant(e),
  tree: StringTree,
  eol_indent: String,
) -> StringTree {
  case eol_indent {
    "" ->
      case unrec {
        None -> string_tree.append(tree, "0")
        Some(data) ->
          case unrecognized.variant_data_format(data) {
            unrecognized.DenseJson -> {
              let raw = unrecognized.variant_data_value(data)
              case bit_array.to_string(raw) {
                Ok(s) if s != "" -> string_tree.append(tree, s)
                _ -> string_tree.append(tree, "0")
              }
            }
            unrecognized.BinaryBytes -> string_tree.append(tree, "0")
          }
      }
    _ -> string_tree.append(tree, json.to_string(json.string("UNKNOWN")))
  }
}

// =============================================================================
// JSON decoding
// =============================================================================

// Converts a dynamic.Dynamic value (parsed from JSON) back to a JSON string.
fn dynamic_to_json_string(d: dynamic.Dynamic) -> String {
  case decode.run(d, decode.int) {
    Ok(n) -> int.to_string(n)
    _ ->
      case decode.run(d, decode.bool) {
        Ok(True) -> "true"
        Ok(False) -> "false"
        _ ->
          case decode.run(d, decode.string) {
            Ok(s) -> json.to_string(json.string(s))
            _ ->
              case decode.run(d, decode.list(decode.dynamic)) {
                Ok(lst) ->
                  "["
                  <> string.join(list.map(lst, dynamic_to_json_string), ",")
                  <> "]"
                _ -> "null"
              }
          }
      }
  }
}

fn enum_decode_json(
  variants_by_number: dict.Dict(Int, VariantAdapter(e)),
  variants_by_name: dict.Dict(String, VariantAdapter(e)),
  removed_numbers: List(Int),
  unknown_default: e,
  wrap_unrecognized: fn(unrecognized.UnrecognizedVariant(e)) -> e,
  d: dynamic.Dynamic,
  keep: Bool,
) -> Result(e, String) {
  // Try as integer: constant variant by number (dense JSON).
  case decode.run(d, decode.int) {
    Ok(n) ->
      case
        resolve_constant_number_keep(
          n,
          variants_by_number,
          removed_numbers,
          unknown_default,
          wrap_unrecognized,
          keep,
        )
      {
        Ok(e) -> Ok(e)
        Error(e) -> Error(e)
      }
    Error(_) ->
      // Try as bool: true=1, false=0.
      case decode.run(d, decode.bool) {
        Ok(b) -> {
          let n = case b {
            True -> 1
            False -> 0
          }
          Ok(resolve_constant_number(
            n,
            variants_by_number,
            removed_numbers,
            unknown_default,
          ))
        }
        Error(_) ->
          // Try as string: constant variant by name (readable JSON).
          case decode.run(d, decode.string) {
            Ok(s) ->
              case dict.get(variants_by_name, s) {
                Error(_) -> Ok(unknown_default)
                Ok(v) ->
                  case v.constant {
                    Some(c) -> Ok(c)
                    None ->
                      Error(
                        "variant '"
                        <> s
                        <> "' is a wrapper variant; expected a constant",
                      )
                  }
              }
            Error(_) ->
              // Try as [number, value]: wrapper variant (dense JSON).
              case decode.run(d, decode.list(decode.dynamic)) {
                Ok([num_d, val_d, ..]) ->
                  case decode.run(num_d, decode.int) {
                    Error(_) -> Ok(unknown_default)
                    Ok(n) ->
                      case list.contains(removed_numbers, n) {
                        True -> Ok(unknown_default)
                        False ->
                          case dict.get(variants_by_number, n) {
                            Error(_) ->
                              case keep {
                                False -> Ok(unknown_default)
                                True -> {
                                  // Store as unrecognized: reconstruct JSON array
                                  let json_bytes =
                                    bit_array.from_string(
                                      "["
                                      <> int.to_string(n)
                                      <> ","
                                      <> dynamic_to_json_string(val_d)
                                      <> "]",
                                    )
                                  Ok(
                                    wrap_unrecognized(
                                      Some(unrecognized.variant_data_from_json(
                                        n,
                                        json_bytes,
                                      )),
                                    ),
                                  )
                                }
                              }
                            Ok(v) -> v.wrap_from_json(val_d)
                          }
                      }
                  }
                Ok(_) -> Ok(unknown_default)
                Error(_) ->
                  // Try as {"kind": ..., "value": ...}: wrapper variant
                  // (readable JSON).
                  case
                    decode.run(d, decode.dict(decode.string, decode.dynamic))
                  {
                    Error(_) -> Ok(unknown_default)
                    Ok(obj) -> {
                      let name = case dict.get(obj, "kind") {
                        Error(_) -> ""
                        Ok(k) -> result.unwrap(decode.run(k, decode.string), "")
                      }
                      case dict.get(variants_by_name, name) {
                        Error(_) -> Ok(unknown_default)
                        Ok(v) ->
                          case v.constant {
                            Some(c) -> Ok(c)
                            None ->
                              case dict.get(obj, "value") {
                                Ok(val_d) -> v.wrap_from_json(val_d)
                                Error(_) ->
                                  Ok(option.unwrap(
                                    v.wrap_default(),
                                    unknown_default,
                                  ))
                              }
                          }
                      }
                    }
                  }
              }
          }
      }
  }
}

fn resolve_constant_number(
  number: Int,
  variants_by_number: dict.Dict(Int, VariantAdapter(e)),
  removed_numbers: List(Int),
  unknown_default: e,
) -> e {
  case list.contains(removed_numbers, number) {
    True -> unknown_default
    False ->
      case dict.get(variants_by_number, number) {
        Error(_) -> unknown_default
        Ok(v) ->
          case v.constant {
            Some(c) -> c
            None ->
              // Wrapper variant seen in constant context: use default payload.
              option.unwrap(v.wrap_default(), unknown_default)
          }
      }
  }
}

fn resolve_constant_number_keep(
  number: Int,
  variants_by_number: dict.Dict(Int, VariantAdapter(e)),
  removed_numbers: List(Int),
  unknown_default: e,
  wrap_unrecognized: fn(unrecognized.UnrecognizedVariant(e)) -> e,
  keep: Bool,
) -> Result(e, String) {
  case list.contains(removed_numbers, number) {
    True -> Ok(unknown_default)
    False ->
      case dict.get(variants_by_number, number) {
        Ok(v) ->
          case v.constant {
            Some(c) -> Ok(c)
            None -> Ok(option.unwrap(v.wrap_default(), unknown_default))
          }
        Error(_) ->
          case keep {
            False -> Ok(unknown_default)
            True -> {
              let json_bytes = bit_array.from_string(int.to_string(number))
              Ok(
                wrap_unrecognized(
                  Some(unrecognized.variant_data_from_json(number, json_bytes)),
                ),
              )
            }
          }
      }
  }
}

// =============================================================================
// Binary encoding
// =============================================================================

fn enum_encode(
  variants: List(VariantAdapter(e)),
  get_kind_ordinal: fn(e) -> Int,
  get_unrecognized: fn(e) -> unrecognized.UnrecognizedVariant(e),
  e: e,
  tree: BytesTree,
) -> BytesTree {
  case get_kind_ordinal(e) {
    0 ->
      // Unknown: re-emit captured bytes if available.
      case get_unrecognized(e) {
        None -> bytes_tree.append(tree, <<0>>)
        Some(data) -> {
          let fmt = unrecognized.variant_data_format(data)
          let bytes = unrecognized.variant_data_value(data)
          case
            fmt == unrecognized.BinaryBytes && bit_array.byte_size(bytes) > 0
          {
            True -> bytes_tree.append(tree, bytes)
            False -> bytes_tree.append(tree, <<0>>)
          }
        }
      }
    ko ->
      case list.drop(variants, ko - 1) |> list.first {
        Error(_) -> bytes_tree.append(tree, <<0>>)
        Ok(v) ->
          case v.constant {
            Some(_) ->
              // Constant variant: encode the variant number as a varint.
              bytes_tree.append(tree, encode_uint32(v.number))
            None -> {
              // Wrapper variant: header byte(s) then the payload.
              let n = v.number
              let t1 = case n >= 1 && n <= 4 {
                True -> {
                  let header_byte = 250 + n
                  bytes_tree.append(tree, <<header_byte>>)
                }
                False ->
                  tree
                  |> bytes_tree.append(<<248>>)
                  |> bytes_tree.append(encode_uint32(n))
              }
              v.encode_payload(e, t1)
            }
          }
      }
  }
}

// =============================================================================
// Binary decoding
// =============================================================================

fn enum_decode_binary(
  variants_by_number: dict.Dict(Int, VariantAdapter(e)),
  removed_numbers: List(Int),
  unknown_default: e,
  wrap_unrecognized: fn(unrecognized.UnrecognizedVariant(e)) -> e,
  bits: BitArray,
  keep: Bool,
) -> Result(#(e, BitArray), String) {
  case bits {
    <<wire, rest:bits>> ->
      case wire < 242 {
        True -> {
          // Constant variant context: decode the full varint starting at `bits`.
          case decode_utils.decode_number(bits) {
            Error(e) -> Error(e)
            Ok(#(0, rest2)) -> Ok(#(unknown_default, rest2))
            Ok(#(number, rest2)) -> {
              let consumed =
                bit_array.byte_size(bits) - bit_array.byte_size(rest2)
              let raw =
                bit_array.slice(bits, 0, consumed) |> result.unwrap(<<>>)
              Ok(#(
                resolve_constant_number_bin(
                  number,
                  variants_by_number,
                  removed_numbers,
                  unknown_default,
                  wrap_unrecognized,
                  keep,
                  raw,
                ),
                rest2,
              ))
            }
          }
        }
        False ->
          // Wrapper variant context: determine the variant number from the header.
          case wire {
            248 ->
              // Number follows as a varint in `rest`.
              case decode_utils.decode_number(rest) {
                Error(e) -> Error(e)
                Ok(#(number, rest2)) ->
                  decode_wrapper_number(
                    number,
                    variants_by_number,
                    removed_numbers,
                    unknown_default,
                    wrap_unrecognized,
                    rest2,
                    keep,
                  )
              }
            251 | 252 | 253 | 254 ->
              decode_wrapper_number(
                wire - 250,
                variants_by_number,
                removed_numbers,
                unknown_default,
                wrap_unrecognized,
                rest,
                keep,
              )
            _ ->
              // Unknown wire byte (242..247, 249, 250, 255): return Unknown.
              Ok(#(unknown_default, rest))
          }
      }
    _ -> Error("unexpected end of input decoding enum")
  }
}

fn resolve_constant_number_bin(
  number: Int,
  variants_by_number: dict.Dict(Int, VariantAdapter(e)),
  removed_numbers: List(Int),
  unknown_default: e,
  wrap_unrecognized: fn(unrecognized.UnrecognizedVariant(e)) -> e,
  keep: Bool,
  raw_bits: BitArray,
) -> e {
  case list.contains(removed_numbers, number) {
    True -> unknown_default
    False ->
      case dict.get(variants_by_number, number) {
        Error(_) ->
          case keep {
            False -> unknown_default
            True -> {
              let ud = unrecognized.variant_data_from_bytes(number, raw_bits)
              wrap_unrecognized(Some(ud))
            }
          }
        Ok(v) ->
          case v.constant {
            Some(c) -> c
            None ->
              // Wrapper variant seen in constant context: use default payload.
              option.unwrap(v.wrap_default(), unknown_default)
          }
      }
  }
}

fn decode_wrapper_number(
  number: Int,
  variants_by_number: dict.Dict(Int, VariantAdapter(e)),
  removed_numbers: List(Int),
  unknown_default: e,
  wrap_unrecognized: fn(unrecognized.UnrecognizedVariant(e)) -> e,
  bits: BitArray,
  keep: Bool,
) -> Result(#(e, BitArray), String) {
  case list.contains(removed_numbers, number) {
    True ->
      case decode_utils.skip_value(bits) {
        Error(e) -> Error(e)
        Ok(rest) -> Ok(#(unknown_default, rest))
      }
    False ->
      case dict.get(variants_by_number, number) {
        Ok(v) -> v.wrap_decode(bits, keep)
        Error(_) ->
          // Unrecognized wrapper variant.
          case keep {
            False ->
              case decode_utils.skip_value(bits) {
                Error(e) -> Error(e)
                Ok(rest) -> Ok(#(unknown_default, rest))
              }
            True -> {
              let header = encode_wrapper_header(number)
              let before_size = bit_array.byte_size(bits)
              case decode_utils.skip_value(bits) {
                Error(e) -> Error(e)
                Ok(rest) -> {
                  let consumed = before_size - bit_array.byte_size(rest)
                  let payload =
                    bit_array.slice(bits, 0, consumed) |> result.unwrap(<<>>)
                  let all_bytes = bit_array.append(header, payload)
                  let ud =
                    unrecognized.variant_data_from_bytes(number, all_bytes)
                  Ok(#(wrap_unrecognized(Some(ud)), rest))
                }
              }
            }
          }
      }
  }
}

// =============================================================================
// Type descriptor
// =============================================================================

fn enum_type_descriptor(
  name: String,
  qualified_name: String,
  module_path: String,
  doc: String,
  variants: List(VariantAdapter(e)),
  removed_numbers: List(Int),
) -> type_descriptor.TypeDescriptor {
  let id = module_path <> ":" <> qualified_name
  let variants_desc =
    list.map(variants, fn(v) {
      case v.type_descriptor() {
        None ->
          type_descriptor.ConstantVariant(
            name: v.name,
            number: v.number,
            doc: v.doc,
          )
        Some(td) ->
          type_descriptor.WrapperVariant(
            name: v.name,
            number: v.number,
            variant_type: td.type_sig,
            doc: v.doc,
          )
      }
    })
  let all_records =
    list.fold(variants, dict.new(), fn(acc, v) {
      case v.type_descriptor() {
        None -> acc
        Some(td) -> dict.merge(acc, td.records)
      }
    })
  let enum_descriptor =
    type_descriptor.EnumDescriptor(
      name: name,
      qualified_name: qualified_name,
      module_path: module_path,
      doc: doc,
      removed_numbers: removed_numbers,
      variants: variants_desc,
    )
  type_descriptor.TypeDescriptor(
    type_sig: type_descriptor.Record(id),
    records: dict.insert(
      all_records,
      id,
      type_descriptor.EnumRecord(enum_descriptor),
    ),
  )
}

// =============================================================================
// Internal helpers
// =============================================================================

fn encode_uint32(n: Int) -> BitArray {
  case n {
    _ if n <= 231 -> <<n>>
    _ if n <= 65_535 -> <<232, n:size(16)-little>>
    _ -> <<233, n:size(32)-little>>
  }
}

fn encode_wrapper_header(number: Int) -> BitArray {
  case number >= 1 && number <= 4 {
    True -> {
      let header_byte = 250 + number
      <<header_byte>>
    }
    False -> bit_array.append(<<248>>, encode_uint32(number))
  }
}
