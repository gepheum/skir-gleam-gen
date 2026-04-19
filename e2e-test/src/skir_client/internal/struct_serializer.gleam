import decode_utils
import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleam/string_tree.{type StringTree}
import serializer
import skir_client/internal/unrecognized
import type_descriptor

/// Stores unrecognized fields encountered while deserializing a struct of type
/// `t`. `None` when deserialization was performed without keeping unrecognized
/// values.
pub type UnrecognizedFields(t) {
  None
  Some(UnrecognizedFieldsData(t))
}

pub opaque type UnrecognizedFieldsData(t) {
  UnrecognizedFieldsData(
    format: unrecognized.UnrecognizedFormat,
    array_len: Int,
    values: BitArray,
    phantom_t: List(t),
  )
}

fn fields_data_from_json(
  array_len: Int,
  json_bytes: BitArray,
) -> UnrecognizedFieldsData(t) {
  UnrecognizedFieldsData(
    format: unrecognized.DenseJson,
    array_len:,
    values: json_bytes,
    phantom_t: [],
  )
}

fn fields_data_from_bytes(
  array_len: Int,
  raw_bytes: BitArray,
) -> UnrecognizedFieldsData(t) {
  UnrecognizedFieldsData(
    format: unrecognized.BinaryBytes,
    array_len:,
    values: raw_bytes,
    phantom_t: [],
  )
}

/// The serializer for a field. Use `Eager` for non-recursive fields (serializer
/// is constructed once), and `Lazy` for recursive fields (serializer is
/// constructed on demand to avoid infinite recursion).
pub type FieldSerializer(f) {
  Eager(serializer.Serializer(f))
  Lazy(fn() -> serializer.Serializer(f))
}

pub type FieldAdapter(s) {
  FieldAdapter(
    name: String,
    number: Int,
    doc: String,
    is_default: fn(s) -> Bool,
    append_json: fn(s, StringTree, String) -> StringTree,
    decode_json: fn(dynamic.Dynamic, s) -> Result(s, String),
    encode: fn(s, BytesTree) -> BytesTree,
    decode: fn(BitArray, s, Bool) -> Result(#(s, BitArray), String),
    type_descriptor: fn() -> type_descriptor.TypeDescriptor,
  )
}

pub fn field_spec_to_field_adapter(
  name name: String,
  number number: Int,
  doc doc: String,
  default default: f,
  type_sig type_sig: type_descriptor.TypeSignature,
  get get: fn(s) -> f,
  set set: fn(s, f) -> s,
  serializer field_serializer: FieldSerializer(f),
) -> FieldAdapter(s) {
  case field_serializer {
    Eager(s) -> {
      let ta = s.adapter
      FieldAdapter(
        name: name,
        number: number,
        doc: doc,
        is_default: fn(acc) { ta.is_default(get(acc)) },
        append_json: fn(acc, tree, eol_indent) {
          ta.append_json(get(acc), tree, eol_indent)
        },
        decode_json: fn(d, acc) {
          case decode.run(d, ta.decode_json(False)) {
            Ok(f_val) -> Ok(set(acc, f_val))
            Error([decode.DecodeError(expected:, found:, ..), ..]) ->
              Error("expected " <> expected <> " but found " <> found)
            Error([]) -> Error("decode error")
          }
        },
        encode: fn(acc, tree) { ta.encode(get(acc), tree) },
        decode: fn(bits, acc, keep_unrecognized) {
          case ta.decode(bits, keep_unrecognized) {
            Ok(#(f_val, rest)) -> Ok(#(set(acc, f_val), rest))
            Error(e) -> Error(e)
          }
        },
        type_descriptor: fn() { ta.type_descriptor() },
      )
    }
    Lazy(f) ->
      FieldAdapter(
        name: name,
        number: number,
        doc: doc,
        is_default: fn(acc) { get(acc) == default },
        append_json: fn(acc, tree, eol_indent) {
          f().adapter.append_json(get(acc), tree, eol_indent)
        },
        decode_json: fn(d, acc) {
          case decode.run(d, f().adapter.decode_json(False)) {
            Ok(f_val) -> Ok(set(acc, f_val))
            Error([decode.DecodeError(expected:, found:, ..), ..]) ->
              Error("expected " <> expected <> " but found " <> found)
            Error([]) -> Error("decode error")
          }
        },
        encode: fn(acc, tree) { f().adapter.encode(get(acc), tree) },
        decode: fn(bits, acc, keep_unrecognized) {
          case f().adapter.decode(bits, keep_unrecognized) {
            Ok(#(f_val, rest)) -> Ok(#(set(acc, f_val), rest))
            Error(e) -> Error(e)
          }
        },
        type_descriptor: fn() {
          type_descriptor.TypeDescriptor(
            type_sig: type_sig,
            records: dict.new(),
          )
        },
      )
  }
}

// =============================================================================
// Helpers for generated decode_dense_json / decode_binary callbacks
// =============================================================================

/// Removes and returns the head of a list, or `None` if empty.
/// Used by generated `decode_dense_json` lambdas to consume one array slot.
pub fn take_slot(
  arr: List(dynamic.Dynamic),
) -> #(option.Option(dynamic.Dynamic), List(dynamic.Dynamic)) {
  case arr {
    [] -> #(option.None, [])
    [h, ..t] -> #(option.Some(h), t)
  }
}

/// Decodes one JSON field value from an optional array element.
/// Returns `default` when the element is absent.
pub fn decode_json_field(
  opt_elem: option.Option(dynamic.Dynamic),
  default: f,
  keep: Bool,
  serializer s: serializer.Serializer(f),
) -> Result(f, String) {
  case opt_elem {
    option.None -> Ok(default)
    option.Some(elem) ->
      case decode.run(elem, s.adapter.decode_json(keep)) {
        Ok(v) -> Ok(v)
        Error(errs) ->
          case errs {
            [decode.DecodeError(expected:, found:, ..)] ->
              Error("expected " <> expected <> " but found " <> found)
            _ -> Error("decode error")
          }
      }
  }
}

/// Decodes one binary field value.
/// Returns `#(default, bits)` when the slot is not active (`active=False`).
pub fn decode_binary_field(
  bits: BitArray,
  active: Bool,
  default: f,
  keep: Bool,
  serializer s: serializer.Serializer(f),
) -> Result(#(f, BitArray), String) {
  case active {
    False -> Ok(#(default, bits))
    True -> s.adapter.decode(bits, keep)
  }
}

/// Skips one binary slot if active, otherwise returns bits unchanged.
pub fn skip_binary_slot(
  bits: BitArray,
  active: Bool,
) -> Result(BitArray, String) {
  case active {
    False -> Ok(bits)
    True -> decode_utils.skip_value(bits)
  }
}

/// Creates unrecognized JSON fields data from the remaining array elements.
/// Returns `None` when `keep=False` or there are no extra elements.
/// Like `decode_json_field`, but returns `None` when the element is absent.
/// Used by generated code for hard-recursive fields.
pub fn decode_json_field_opt(
  opt_elem: option.Option(dynamic.Dynamic),
  keep: Bool,
  serializer s: serializer.Serializer(f),
) -> Result(option.Option(f), String) {
  case opt_elem {
    option.None -> Ok(option.None)
    option.Some(elem) ->
      case decode.run(elem, s.adapter.decode_json(keep)) {
        Ok(v) -> Ok(option.Some(v))
        Error(errs) ->
          case errs {
            [decode.DecodeError(expected:, found:, ..)] ->
              Error("expected " <> expected <> " but found " <> found)
            _ -> Error("decode error")
          }
      }
  }
}

/// Like `decode_binary_field`, but returns `None` when the slot is inactive.
/// Used by generated code for hard-recursive fields.
pub fn decode_binary_field_opt(
  bits: BitArray,
  active: Bool,
  keep: Bool,
  serializer s: serializer.Serializer(f),
) -> Result(#(option.Option(f), BitArray), String) {
  case active {
    False -> Ok(#(option.None, bits))
    True ->
      case s.adapter.decode(bits, keep) {
        Ok(#(v, rest)) -> Ok(#(option.Some(v), rest))
        Error(e) -> Error(e)
      }
  }
}

pub fn make_unrecognized_fields_json(
  extra_elements: List(dynamic.Dynamic),
  arr_len: Int,
  keep: Bool,
) -> UnrecognizedFields(s) {
  case keep && !list.is_empty(extra_elements) {
    False -> None
    True -> {
      let extra_json =
        "["
        <> string.join(list.map(extra_elements, dynamic_to_json_string), ",")
        <> "]"
      Some(fields_data_from_json(arr_len, bit_array.from_string(extra_json)))
    }
  }
}

pub fn new_serializer(
  name name: String,
  qualified_name qualified_name: String,
  module_path module_path: String,
  doc doc: String,
  ordered_fields ordered_fields: List(FieldAdapter(s)),
  default default: s,
  get_unrecognized get_unrecognized: fn(s) -> UnrecognizedFields(s),
  set_unrecognized set_unrecognized: fn(s, UnrecognizedFields(s)) -> s,
  removed_numbers removed_numbers: List(Int),
  recognized_slot_count recognized_slot_count: Int,
  decode_dense_json decode_dense_json: fn(List(dynamic.Dynamic), Bool) ->
    Result(s, String),
  decode_binary decode_binary: fn(BitArray, Int, Bool) ->
    Result(#(s, BitArray), String),
) -> serializer.Serializer(s) {
  serializer.make_serializer(
    serializer.make_type_adapter(
      is_default: fn(s) {
        struct_is_default(ordered_fields, get_unrecognized, s)
      },
      append_json: fn(s, tree, eol_indent) {
        struct_append_json(
          ordered_fields,
          get_unrecognized,
          recognized_slot_count,
          s,
          tree,
          eol_indent,
        )
      },
      decode_json: fn(keep) {
        decode.dynamic
        |> decode.then(fn(d) {
          case keep {
            False ->
              case
                struct_decode_json(
                  ordered_fields,
                  decode_dense_json,
                  d,
                  default,
                )
              {
                Ok(s) -> decode.success(s)
                Error(msg) -> decode.failure(default, msg)
              }
            True ->
              case
                struct_decode_json_keep(
                  ordered_fields,
                  decode_dense_json,
                  d,
                  default,
                )
              {
                Ok(s) -> decode.success(s)
                Error(msg) -> decode.failure(default, msg)
              }
          }
        })
      },
      encode: fn(s, tree) {
        struct_encode(
          ordered_fields,
          get_unrecognized,
          recognized_slot_count,
          s,
          tree,
        )
      },
      decode: fn(bits, keep_unrecognized) {
        struct_decode(
          ordered_fields,
          set_unrecognized,
          recognized_slot_count,
          decode_binary,
          bits,
          default,
          keep_unrecognized,
        )
      },
      type_descriptor: fn() {
        let id = module_path <> ":" <> qualified_name
        let field_tds = list.map(ordered_fields, fn(f) { f.type_descriptor() })
        let struct_fields =
          list.map2(ordered_fields, field_tds, fn(f, ftd) {
            type_descriptor.StructField(
              name: f.name,
              number: f.number,
              field_type: ftd.type_sig,
              doc: f.doc,
            )
          })
        let all_records =
          list.fold(field_tds, dict.new(), fn(acc, ftd) {
            dict.merge(acc, ftd.records)
          })
        let struct_descriptor =
          type_descriptor.StructDescriptor(
            name: name,
            qualified_name: qualified_name,
            module_path: module_path,
            doc: doc,
            removed_numbers: removed_numbers,
            fields: struct_fields,
          )
        type_descriptor.TypeDescriptor(
          type_sig: type_descriptor.Record(id),
          records: dict.insert(
            all_records,
            id,
            type_descriptor.StructRecord(struct_descriptor),
          ),
        )
      },
    ),
  )
}

// =============================================================================
// TypeAdapter method implementations
// =============================================================================

fn struct_is_default(
  fields: List(FieldAdapter(s)),
  get_unrecognized: fn(s) -> UnrecognizedFields(s),
  s: s,
) -> Bool {
  case get_unrecognized(s) {
    Some(_) -> False
    None -> list.all(fields, fn(f) { f.is_default(s) })
  }
}

fn struct_append_json(
  fields: List(FieldAdapter(s)),
  get_unrecognized: fn(s) -> UnrecognizedFields(s),
  recognized_slot_count: Int,
  s: s,
  tree: StringTree,
  eol_indent: String,
) -> StringTree {
  case eol_indent {
    "" ->
      append_dense_json(
        fields,
        get_unrecognized,
        recognized_slot_count,
        s,
        tree,
      )
    _ -> append_readable_json(fields, s, tree, eol_indent)
  }
}

fn struct_encode(
  fields: List(FieldAdapter(s)),
  get_unrecognized: fn(s) -> UnrecognizedFields(s),
  recognized_slot_count: Int,
  s: s,
  tree: BytesTree,
) -> BytesTree {
  let unrec = get_unrecognized(s)
  let #(total_slot_count, recognized_slot_count, extra_bytes) = case unrec {
    Some(u) -> {
      let fmt = u.format
      let vals = u.values
      case fmt == unrecognized.BinaryBytes && bit_array.byte_size(vals) > 0 {
        True -> {
          #(u.array_len, recognized_slot_count, option.Some(vals))
        }
        False -> {
          let c = get_slot_count(fields, s)
          #(c, c, option.None)
        }
      }
    }
    None -> {
      let c = get_slot_count(fields, s)
      #(c, c, option.None)
    }
  }
  let tree = encode_slot_count(total_slot_count, tree)
  let tree = encode_slots_binary(fields, s, 0, recognized_slot_count, tree)
  case extra_bytes {
    option.Some(bytes) -> bytes_tree.append(tree, bytes)
    option.None -> tree
  }
}

fn struct_decode(
  _fields: List(FieldAdapter(s)),
  set_unrecognized: fn(s, UnrecognizedFields(s)) -> s,
  recognized_slot_count: Int,
  decode_binary: fn(BitArray, Int, Bool) -> Result(#(s, BitArray), String),
  bits: BitArray,
  s: s,
  keep_unrecognized: Bool,
) -> Result(#(s, BitArray), String) {
  case bits {
    <<wire, rest:bits>> ->
      case wire {
        0 | 246 -> Ok(#(s, rest))
        _ ->
          case decode_slot_count(wire, rest) {
            Error(e) -> Error(e)
            Ok(#(slot_count, rest2)) -> {
              let slots_to_fill = int.min(slot_count, recognized_slot_count)
              case decode_binary(rest2, slots_to_fill, keep_unrecognized) {
                Error(e) -> Error(e)
                Ok(#(s2, rest3)) -> {
                  case slot_count > recognized_slot_count {
                    False -> Ok(#(s2, rest3))
                    True -> {
                      let extra = slot_count - recognized_slot_count
                      case keep_unrecognized {
                        True ->
                          capture_unrecognized_bytes(
                            set_unrecognized,
                            s2,
                            slot_count,
                            extra,
                            rest3,
                          )
                        False ->
                          case decode_utils.skip_n_values(extra, rest3) {
                            Error(e) -> Error(e)
                            Ok(remaining) -> Ok(#(s2, remaining))
                          }
                      }
                    }
                  }
                }
              }
            }
          }
      }
    _ -> Error("unexpected end of input")
  }
}

// =============================================================================
// Dense JSON helpers
// =============================================================================

fn append_dense_json(
  fields: List(FieldAdapter(s)),
  get_unrecognized: fn(s) -> UnrecognizedFields(s),
  recognized_slot_count: Int,
  s: s,
  tree: StringTree,
) -> StringTree {
  let tree = string_tree.append(tree, "[")
  let unrec = get_unrecognized(s)
  let tree = case unrec {
    Some(u) -> {
      let fmt = u.format
      let vals = u.values
      case fmt == unrecognized.DenseJson && bit_array.byte_size(vals) > 0 {
        True -> {
          let tree =
            append_json_slots(fields, s, 0, recognized_slot_count, tree)
          let extra_str = case bit_array.to_string(vals) {
            Ok(raw) ->
              raw
              |> string.trim
              |> string.drop_start(1)
              |> string.drop_end(1)
              |> string.trim
            Error(_) -> ""
          }
          case extra_str {
            "" -> tree
            _ -> {
              let prefix = case recognized_slot_count > 0 {
                True -> ","
                False -> ""
              }
              string_tree.append(tree, prefix <> extra_str)
            }
          }
        }
        False -> {
          let slot_count = get_slot_count(fields, s)
          append_json_slots(fields, s, 0, slot_count, tree)
        }
      }
    }
    None -> {
      let slot_count = get_slot_count(fields, s)
      append_json_slots(fields, s, 0, slot_count, tree)
    }
  }
  string_tree.append(tree, "]")
}

fn append_readable_json(
  fields: List(FieldAdapter(s)),
  s: s,
  tree: StringTree,
  eol_indent: String,
) -> StringTree {
  let child_indent = eol_indent <> "  "
  let tree = string_tree.append(tree, "{")
  let #(tree, any) =
    list.fold(fields, #(tree, False), fn(pair, f) {
      let #(t, had_any) = pair
      case f.is_default(s) {
        True -> #(t, had_any)
        False -> {
          let t = case had_any {
            True -> string_tree.append(t, ",")
            False -> t
          }
          let t = string_tree.append(t, child_indent)
          let t = string_tree.append(t, json.to_string(json.string(f.name)))
          let t = string_tree.append(t, ": ")
          let t = f.append_json(s, t, child_indent)
          #(t, True)
        }
      }
    })
  let tree = case any {
    True -> string_tree.append(tree, eol_indent)
    False -> tree
  }
  string_tree.append(tree, "}")
}

fn append_json_slots(
  fields: List(FieldAdapter(s)),
  s: s,
  i: Int,
  count: Int,
  tree: StringTree,
) -> StringTree {
  case i >= count {
    True -> tree
    False -> {
      let tree = case i > 0 {
        True -> string_tree.append(tree, ",")
        False -> tree
      }
      let #(tree, next_fields) = case fields {
        [f, ..rest] if f.number == i -> #(f.append_json(s, tree, ""), rest)
        _ -> #(string_tree.append(tree, "0"), fields)
      }
      append_json_slots(next_fields, s, i + 1, count, tree)
    }
  }
}

// =============================================================================
// JSON decode helpers
// =============================================================================

fn struct_decode_json(
  fields: List(FieldAdapter(s)),
  decode_dense_json: fn(List(dynamic.Dynamic), Bool) -> Result(s, String),
  d: dynamic.Dynamic,
  s: s,
) -> Result(s, String) {
  case decode.run(d, decode.list(decode.dynamic)) {
    Ok(arr) -> decode_dense_json(arr, False)
    Error(_) ->
      case decode.run(d, decode.dict(decode.string, decode.dynamic)) {
        Ok(obj) -> from_readable_json(fields, obj, s)
        Error(_) -> Ok(s)
      }
  }
}

fn struct_decode_json_keep(
  fields: List(FieldAdapter(s)),
  decode_dense_json: fn(List(dynamic.Dynamic), Bool) -> Result(s, String),
  d: dynamic.Dynamic,
  s: s,
) -> Result(s, String) {
  case decode.run(d, decode.list(decode.dynamic)) {
    Ok(arr) -> decode_dense_json(arr, True)
    Error(_) ->
      case decode.run(d, decode.dict(decode.string, decode.dynamic)) {
        Ok(obj) -> from_readable_json(fields, obj, s)
        Error(_) -> Ok(s)
      }
  }
}

// Converts a dynamic.Dynamic value (parsed from JSON) back to a JSON string.
fn dynamic_to_json_string(d: dynamic.Dynamic) -> String {
  case decode.run(d, decode.int) {
    Ok(n) -> int.to_string(n)
    _ ->
      case decode.run(d, decode.bool) {
        Ok(True) -> "true"
        Ok(False) -> "false"
        _ ->
          case decode.run(d, decode.float) {
            Ok(f) -> float.to_string(f)
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
}

fn from_readable_json(
  fields: List(FieldAdapter(s)),
  obj: dict.Dict(String, dynamic.Dynamic),
  s: s,
) -> Result(s, String) {
  list_fold_result(fields, s, fn(acc, f) {
    case dict.get(obj, f.name) {
      Error(_) -> Ok(acc)
      Ok(v) -> f.decode_json(v, acc)
    }
  })
}

// =============================================================================
// Binary encode helpers
// =============================================================================

fn encode_slot_count(n: Int, tree: BytesTree) -> BytesTree {
  case n <= 3 {
    True -> {
      let header = 246 + n
      bytes_tree.append(tree, <<header>>)
    }
    False ->
      tree
      |> bytes_tree.append(<<250>>)
      |> bytes_tree.append(encode_uint32(n))
  }
}

fn encode_uint32(n: Int) -> BitArray {
  case n {
    _ if n <= 231 -> <<n>>
    _ if n <= 65_535 -> <<232, n:size(16)-little>>
    _ -> <<233, n:size(32)-little>>
  }
}

fn encode_slots_binary(
  fields: List(FieldAdapter(s)),
  s: s,
  i: Int,
  count: Int,
  tree: BytesTree,
) -> BytesTree {
  case i >= count {
    True -> tree
    False -> {
      let #(tree, next_fields) = case fields {
        [f, ..rest] if f.number == i -> #(f.encode(s, tree), rest)
        _ -> #(bytes_tree.append(tree, <<0>>), fields)
      }
      encode_slots_binary(next_fields, s, i + 1, count, tree)
    }
  }
}

// =============================================================================
// Binary decode helpers
// =============================================================================

fn decode_slot_count(
  wire: Int,
  rest: BitArray,
) -> Result(#(Int, BitArray), String) {
  case wire {
    250 -> decode_utils.decode_number(rest)
    247 | 248 | 249 -> Ok(#(wire - 246, rest))
    _ -> Error("unexpected wire byte for struct: " <> int.to_string(wire))
  }
}

fn capture_unrecognized_bytes(
  set_unrecognized: fn(s, UnrecognizedFields(s)) -> s,
  s: s,
  total_slot_count: Int,
  extra: Int,
  rest3: BitArray,
) -> Result(#(s, BitArray), String) {
  let before_size = bit_array.byte_size(rest3)
  case decode_utils.skip_n_values(extra, rest3) {
    Error(e) -> Error(e)
    Ok(remaining) -> {
      let consumed = before_size - bit_array.byte_size(remaining)
      case rest3 {
        <<captured:bytes-size(consumed), _:bits>> -> {
          let new_s =
            set_unrecognized(
              s,
              Some(fields_data_from_bytes(total_slot_count, captured)),
            )
          Ok(#(new_s, remaining))
        }
        _ -> Ok(#(s, remaining))
      }
    }
  }
}

// =============================================================================
// Utility helpers
// =============================================================================

fn get_slot_count(fields: List(FieldAdapter(s)), s: s) -> Int {
  list.fold(fields, 0, fn(max_so_far, f) {
    case f.is_default(s) {
      True -> max_so_far
      False -> int.max(max_so_far, f.number + 1)
    }
  })
}

fn list_fold_result(
  lst: List(a),
  acc: b,
  f: fn(b, a) -> Result(b, String),
) -> Result(b, String) {
  case lst {
    [] -> Ok(acc)
    [first, ..rest] ->
      case f(acc, first) {
        Error(e) -> Error(e)
        Ok(new_acc) -> list_fold_result(rest, new_acc, f)
      }
  }
}
