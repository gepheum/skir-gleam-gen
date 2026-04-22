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
import gleam/result
import gleam/string
import internal/decode_utils
import internal/json_utils
import internal/unrecognized
import serializer.{type UnrecognizedValues, Drop, Keep}
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
    to_json: fn(s, Bool) -> json.Json,
    decode_json: fn(s, UnrecognizedValues) -> decode.Decoder(s),
    encode: fn(s, BytesTree) -> BytesTree,
    decode: fn(BitArray, s, UnrecognizedValues) ->
      Result(#(s, BitArray), String),
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
      let ta = s.internal_adapter
      FieldAdapter(
        name: name,
        number: number,
        doc: doc,
        is_default: fn(acc) { ta.is_default(get(acc)) },
        to_json: fn(acc, readable) { ta.to_json(get(acc), readable) },
        decode_json: fn(acc, keep) {
          decode.map(ta.decode_json(keep), fn(f_val) { set(acc, f_val) })
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
        to_json: fn(acc, readable) {
          f().internal_adapter.to_json(get(acc), readable)
        },
        decode_json: fn(acc, keep) {
          decode.map(f().internal_adapter.decode_json(keep), fn(f_val) {
            set(acc, f_val)
          })
        },
        encode: fn(acc, tree) { f().internal_adapter.encode(get(acc), tree) },
        decode: fn(bits, acc, keep_unrecognized) {
          case f().internal_adapter.decode(bits, keep_unrecognized) {
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
  keep: UnrecognizedValues,
  serializer s: serializer.Serializer(f),
) -> Result(f, String) {
  case opt_elem {
    option.None -> Ok(default)
    option.Some(elem) ->
      decode.run(elem, s.internal_adapter.decode_json(keep))
      |> result.map_error(json_utils.decode_errors_to_string)
  }
}

/// Decodes one binary field value.
/// Returns `#(default, bits)` when the slot is not active (`active=False`).
pub fn decode_binary_field(
  bits: BitArray,
  active: Bool,
  default: f,
  keep: UnrecognizedValues,
  serializer s: serializer.Serializer(f),
) -> Result(#(f, BitArray), String) {
  case active {
    False -> Ok(#(default, bits))
    True -> s.internal_adapter.decode(bits, keep)
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
  keep: UnrecognizedValues,
  serializer s: serializer.Serializer(f),
) -> Result(option.Option(f), String) {
  case opt_elem {
    option.None -> Ok(option.None)
    option.Some(elem) ->
      decode.run(elem, s.internal_adapter.decode_json(keep))
      |> result.map_error(json_utils.decode_errors_to_string)
      |> result.map(option.Some)
  }
}

/// Like `decode_binary_field`, but returns `None` when the slot is inactive.
/// Used by generated code for hard-recursive fields.
pub fn decode_binary_field_opt(
  bits: BitArray,
  active: Bool,
  keep: UnrecognizedValues,
  serializer s: serializer.Serializer(f),
) -> Result(#(option.Option(f), BitArray), String) {
  case active {
    False -> Ok(#(option.None, bits))
    True ->
      case s.internal_adapter.decode(bits, keep) {
        Ok(#(v, rest)) -> Ok(#(option.Some(v), rest))
        Error(e) -> Error(e)
      }
  }
}

pub fn make_unrecognized_fields_json(
  extra_elements: List(dynamic.Dynamic),
  arr_len: Int,
  keep: UnrecognizedValues,
) -> UnrecognizedFields(s) {
  case keep {
    Drop -> None
    Keep ->
      case extra_elements {
        [] -> None
        _ -> {
          let extra_json =
            "["
            <> string.join(
              list.map(extra_elements, dynamic_to_json_string),
              ",",
            )
            <> "]"
          Some(fields_data_from_json(arr_len, bit_array.from_string(extra_json)))
        }
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
  decode_dense_json decode_dense_json: fn(
    List(dynamic.Dynamic),
    UnrecognizedValues,
  ) ->
    Result(s, String),
  decode_binary decode_binary: fn(BitArray, Int, UnrecognizedValues) ->
    Result(#(s, BitArray), String),
) -> serializer.Serializer(s) {
  let fields_reversed = list.reverse(ordered_fields)
  serializer.make_serializer(
    serializer.make_type_adapter(
      is_default: fn(s) {
        struct_is_default(ordered_fields, get_unrecognized, s)
      },
      to_json: fn(s, readable) {
        struct_append_json(
          ordered_fields,
          fields_reversed,
          get_unrecognized,
          recognized_slot_count,
          s,
          readable,
        )
      },
      decode_json: fn(keep) {
        use d <- decode.then(decode.dynamic)
        case
          struct_decode_json(
            ordered_fields,
            decode_dense_json,
            d,
            default,
            keep,
          )
        {
          Ok(s) -> decode.success(s)
          Error(msg) -> decode.failure(default, msg)
        }
      },
      encode: fn(s, tree) {
        struct_encode(
          ordered_fields,
          fields_reversed,
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
  fields_reversed: List(FieldAdapter(s)),
  get_unrecognized: fn(s) -> UnrecognizedFields(s),
  recognized_slot_count: Int,
  s: s,
  readable: Bool,
) -> json.Json {
  case readable {
    False ->
      append_dense_json(
        fields,
        fields_reversed,
        get_unrecognized,
        recognized_slot_count,
        s,
      )
    True -> append_readable_json(fields, s)
  }
}

fn struct_encode(
  fields: List(FieldAdapter(s)),
  fields_reversed: List(FieldAdapter(s)),
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
          let c = get_slot_count(fields_reversed, s)
          #(c, c, option.None)
        }
      }
    }
    None -> {
      let c = get_slot_count(fields_reversed, s)
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
  decode_binary: fn(BitArray, Int, UnrecognizedValues) ->
    Result(#(s, BitArray), String),
  bits: BitArray,
  s: s,
  keep_unrecognized: UnrecognizedValues,
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
                        Keep ->
                          capture_unrecognized_bytes(
                            set_unrecognized,
                            s2,
                            slot_count,
                            extra,
                            rest3,
                          )
                        Drop ->
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
  fields_reversed: List(FieldAdapter(s)),
  get_unrecognized: fn(s) -> UnrecognizedFields(s),
  recognized_slot_count: Int,
  s: s,
) -> json.Json {
  let unrec = get_unrecognized(s)
  let dense_items = case unrec {
    Some(u) -> {
      let fmt = u.format
      let vals = u.values
      case fmt == unrecognized.DenseJson && bit_array.byte_size(vals) > 0 {
        True -> {
          let known = append_json_slots(fields, s, 0, recognized_slot_count, [])
          let extra_values = case bit_array.to_string(vals) {
            Ok(raw) ->
              case json.parse(from: raw, using: decode.list(decode.dynamic)) {
                Ok(vs) -> list.map(vs, dynamic_to_json)
                Error(_) -> []
              }
            Error(_) -> []
          }
          list.append(known, extra_values)
        }
        False -> {
          let slot_count = get_slot_count(fields_reversed, s)
          append_json_slots(fields, s, 0, slot_count, [])
        }
      }
    }
    None -> {
      let slot_count = get_slot_count(fields_reversed, s)
      append_json_slots(fields, s, 0, slot_count, [])
    }
  }
  json.preprocessed_array(dense_items)
}

fn append_readable_json(fields: List(FieldAdapter(s)), s: s) -> json.Json {
  let pairs =
    list.filter_map(fields, fn(f) {
      case f.is_default(s) {
        True -> Error(Nil)
        False -> Ok(#(f.name, f.to_json(s, True)))
      }
    })
  json.object(pairs)
}

fn append_json_slots(
  fields: List(FieldAdapter(s)),
  s: s,
  i: Int,
  count: Int,
  acc: List(json.Json),
) -> List(json.Json) {
  case i >= count {
    True -> list.reverse(acc)
    False -> {
      let #(value, next_fields) = case fields {
        [f, ..rest] if f.number == i -> #(f.to_json(s, False), rest)
        _ -> #(json.int(0), fields)
      }
      append_json_slots(next_fields, s, i + 1, count, [value, ..acc])
    }
  }
}

// =============================================================================
// JSON decode helpers
// =============================================================================

fn struct_decode_json(
  fields: List(FieldAdapter(s)),
  decode_dense_json: fn(List(dynamic.Dynamic), UnrecognizedValues) ->
    Result(s, String),
  d: dynamic.Dynamic,
  s: s,
  keep: UnrecognizedValues,
) -> Result(s, String) {
  case decode.run(d, decode.list(decode.dynamic)) {
    Ok(arr) -> decode_dense_json(arr, keep)
    Error(_) ->
      case decode.run(d, decode.dict(decode.string, decode.dynamic)) {
        Ok(obj) -> from_readable_json(fields, obj, s, keep)
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

fn dynamic_to_json(d: dynamic.Dynamic) -> json.Json {
  case decode.run(d, decode.int) {
    Ok(n) -> json.int(n)
    _ ->
      case decode.run(d, decode.bool) {
        Ok(b) -> json.bool(b)
        _ ->
          case decode.run(d, decode.float) {
            Ok(f) -> json.float(f)
            _ ->
              case decode.run(d, decode.string) {
                Ok(s) -> json.string(s)
                _ ->
                  case decode.run(d, decode.list(decode.dynamic)) {
                    Ok(lst) ->
                      json.preprocessed_array(list.map(lst, dynamic_to_json))
                    _ ->
                      case
                        decode.run(
                          d,
                          decode.dict(decode.string, decode.dynamic),
                        )
                      {
                        Ok(obj) ->
                          json.object(
                            dict.to_list(obj)
                            |> list.map(fn(p) { #(p.0, dynamic_to_json(p.1)) }),
                          )
                        _ -> json.null()
                      }
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
  keep: UnrecognizedValues,
) -> Result(s, String) {
  list.try_fold(fields, s, fn(acc, f) {
    case dict.get(obj, f.name) {
      Error(_) -> Ok(acc)
      Ok(v) ->
        decode.run(v, f.decode_json(acc, keep))
        |> result.map_error(json_utils.decode_errors_to_string)
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
      |> bytes_tree.append(decode_utils.encode_uint32(n))
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

fn get_slot_count(fields_reversed: List(FieldAdapter(s)), s: s) -> Int {
  // Fields are ordered by number ascending, so iterating in reverse lets us
  // stop at the first (highest-numbered) non-default field.
  case list.find(fields_reversed, fn(f) { !f.is_default(s) }) {
    Ok(f) -> f.number + 1
    Error(_) -> 0
  }
}
