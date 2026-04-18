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
import gleam/string
import gleam/string_tree.{type StringTree}
import serializer
import type_descriptor
import unrecognized

pub type Recursivity {
  Recursive
  NotRecursive
}

pub type FieldSpec(s, f) {
  FieldSpec(
    name: String,
    number: Int,
    doc: String,
    get: fn(s) -> f,
    set: fn(s, f) -> s,
    serializer: fn() -> serializer.Serializer(f),
    recursive: Recursivity,
  )
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

pub fn field_spec_to_field_adapter(spec: FieldSpec(s, f)) -> FieldAdapter(s) {
  case spec.recursive {
    NotRecursive -> {
      let ta = spec.serializer().adapter
      FieldAdapter(
        name: spec.name,
        number: spec.number,
        doc: spec.doc,
        is_default: fn(s) { ta.is_default(spec.get(s)) },
        append_json: fn(s, tree, eol_indent) {
          ta.append_json(spec.get(s), tree, eol_indent)
        },
        decode_json: fn(d, s) {
          case decode.run(d, ta.decode_json) {
            Ok(f_val) -> Ok(spec.set(s, f_val))
            Error([decode.DecodeError(expected:, found:, ..), ..]) ->
              Error("expected " <> expected <> " but found " <> found)
            Error([]) -> Error("decode error")
          }
        },
        encode: fn(s, tree) { ta.encode(spec.get(s), tree) },
        decode: fn(bits, s, keep_unrecognized) {
          case ta.decode(bits, keep_unrecognized) {
            Ok(#(f_val, rest)) -> Ok(#(spec.set(s, f_val), rest))
            Error(e) -> Error(e)
          }
        },
        type_descriptor: fn() { ta.type_descriptor() },
      )
    }
    Recursive ->
      FieldAdapter(
        name: spec.name,
        number: spec.number,
        doc: spec.doc,
        is_default: fn(s) { spec.serializer().adapter.is_default(spec.get(s)) },
        append_json: fn(s, tree, eol_indent) {
          spec.serializer().adapter.append_json(spec.get(s), tree, eol_indent)
        },
        decode_json: fn(d, s) {
          case decode.run(d, spec.serializer().adapter.decode_json) {
            Ok(f_val) -> Ok(spec.set(s, f_val))
            Error([decode.DecodeError(expected:, found:, ..), ..]) ->
              Error("expected " <> expected <> " but found " <> found)
            Error([]) -> Error("decode error")
          }
        },
        encode: fn(s, tree) {
          spec.serializer().adapter.encode(spec.get(s), tree)
        },
        decode: fn(bits, s, keep_unrecognized) {
          case spec.serializer().adapter.decode(bits, keep_unrecognized) {
            Ok(#(f_val, rest)) -> Ok(#(spec.set(s, f_val), rest))
            Error(e) -> Error(e)
          }
        },
        type_descriptor: fn() { spec.serializer().adapter.type_descriptor() },
      )
  }
}

pub fn new_serializer(
  name name: String,
  qualified_name qualified_name: String,
  module_path module_path: String,
  doc doc: String,
  ordered_fields ordered_fields: List(FieldAdapter(s)),
  default default: s,
  get_unrecognized get_unrecognized: fn(s) -> unrecognized.UnrecognizedFields(s),
  set_unrecognized set_unrecognized: fn(s, unrecognized.UnrecognizedFields(s)) ->
    s,
  removed_numbers removed_numbers: List(Int),
  recognized_slot_count recognized_slot_count: Int,
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
      decode_json: decode.dynamic
        |> decode.then(fn(d) {
          case
            struct_decode_json(
              ordered_fields,
              recognized_slot_count,
              d,
              default,
            )
          {
            Ok(s) -> decode.success(s)
            Error(msg) -> decode.failure(default, msg)
          }
        }),
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
  get_unrecognized: fn(s) -> unrecognized.UnrecognizedFields(s),
  s: s,
) -> Bool {
  case get_unrecognized(s) {
    Some(_) -> False
    None -> list.all(fields, fn(f) { f.is_default(s) })
  }
}

fn struct_append_json(
  fields: List(FieldAdapter(s)),
  get_unrecognized: fn(s) -> unrecognized.UnrecognizedFields(s),
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

fn struct_decode_json(
  fields: List(FieldAdapter(s)),
  recognized_slot_count: Int,
  d: dynamic.Dynamic,
  s: s,
) -> Result(s, String) {
  case decode.run(d, decode.list(decode.dynamic)) {
    Ok(arr) -> from_dense_json(fields, recognized_slot_count, arr, s, False)
    Error(_) ->
      case decode.run(d, decode.dict(decode.string, decode.dynamic)) {
        Ok(obj) -> from_readable_json(fields, obj, s)
        Error(_) -> Ok(s)
      }
  }
}

fn struct_encode(
  fields: List(FieldAdapter(s)),
  get_unrecognized: fn(s) -> unrecognized.UnrecognizedFields(s),
  recognized_slot_count: Int,
  s: s,
  tree: BytesTree,
) -> BytesTree {
  let unrec = get_unrecognized(s)
  let #(total_slot_count, recognized_slot_count, extra_bytes) = case unrec {
    Some(u) -> {
      let fmt = unrecognized.fields_data_format(u)
      let vals = unrecognized.fields_data_values(u)
      case fmt == unrecognized.BinaryBytes && bit_array.byte_size(vals) > 0 {
        True -> {
          #(
            unrecognized.fields_data_array_len(u),
            recognized_slot_count,
            Some(vals),
          )
        }
        False -> {
          let c = get_slot_count(fields, s)
          #(c, c, None)
        }
      }
    }
    None -> {
      let c = get_slot_count(fields, s)
      #(c, c, None)
    }
  }
  let tree = encode_slot_count(total_slot_count, tree)
  let tree = encode_slots_binary(fields, s, 0, recognized_slot_count, tree)
  case extra_bytes {
    Some(bytes) -> bytes_tree.append(tree, bytes)
    None -> tree
  }
}

fn struct_decode(
  fields: List(FieldAdapter(s)),
  set_unrecognized: fn(s, unrecognized.UnrecognizedFields(s)) -> s,
  recognized_slot_count: Int,
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
              case
                decode_slots(
                  fields,
                  s,
                  0,
                  slots_to_fill,
                  rest2,
                  keep_unrecognized,
                )
              {
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
  get_unrecognized: fn(s) -> unrecognized.UnrecognizedFields(s),
  recognized_slot_count: Int,
  s: s,
  tree: StringTree,
) -> StringTree {
  let tree = string_tree.append(tree, "[")
  let unrec = get_unrecognized(s)
  let tree = case unrec {
    Some(u) -> {
      let fmt = unrecognized.fields_data_format(u)
      let vals = unrecognized.fields_data_values(u)
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

fn from_dense_json(
  fields: List(FieldAdapter(s)),
  recognized_slot_count: Int,
  arr: List(dynamic.Dynamic),
  s: s,
  _keep_unrecognized: Bool,
) -> Result(s, String) {
  let num_to_fill = int.min(list.length(arr), recognized_slot_count)
  // fields are sorted by number; walk both lists linearly
  from_dense_json_loop(fields, arr, 0, num_to_fill, s)
}

fn from_dense_json_loop(
  fields: List(FieldAdapter(s)),
  arr: List(dynamic.Dynamic),
  pos: Int,
  limit: Int,
  s: s,
) -> Result(s, String) {
  case fields {
    [] -> Ok(s)
    [f, ..rest_fields] ->
      case f.number >= limit {
        True -> Ok(s)
        False -> {
          let #(elem_opt, arr_rest, new_pos) = advance_to(arr, pos, f.number)
          case elem_opt {
            None -> Ok(s)
            Some(elem) ->
              case f.decode_json(elem, s) {
                Error(e) -> Error(e)
                Ok(new_s) ->
                  from_dense_json_loop(
                    rest_fields,
                    arr_rest,
                    new_pos,
                    limit,
                    new_s,
                  )
              }
          }
        }
      }
  }
}

fn advance_to(lst: List(a), pos: Int, target: Int) -> #(Option(a), List(a), Int) {
  case pos >= target {
    True ->
      case lst {
        [] -> #(None, [], pos)
        [first, ..rest] -> #(Some(first), rest, pos + 1)
      }
    False ->
      case lst {
        [] -> #(None, [], pos)
        [_, ..rest] -> advance_to(rest, pos + 1, target)
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

fn decode_slots(
  fields: List(FieldAdapter(s)),
  s: s,
  i: Int,
  count: Int,
  bits: BitArray,
  keep_unrecognized: Bool,
) -> Result(#(s, BitArray), String) {
  case i >= count {
    True -> Ok(#(s, bits))
    False ->
      case fields {
        [f, ..rest_fields] if f.number == i ->
          case f.decode(bits, s, keep_unrecognized) {
            Error(e) -> Error(e)
            Ok(#(new_s, rest)) ->
              decode_slots(
                rest_fields,
                new_s,
                i + 1,
                count,
                rest,
                keep_unrecognized,
              )
          }
        _ ->
          case decode_utils.skip_value(bits) {
            Error(e) -> Error(e)
            Ok(rest) ->
              decode_slots(fields, s, i + 1, count, rest, keep_unrecognized)
          }
      }
  }
}

fn capture_unrecognized_bytes(
  set_unrecognized: fn(s, unrecognized.UnrecognizedFields(s)) -> s,
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
              Some(unrecognized.fields_data_from_bytes(
                total_slot_count,
                captured,
              )),
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
