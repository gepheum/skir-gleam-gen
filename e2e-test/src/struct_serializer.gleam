import gleam/bytes_tree.{type BytesTree}
import gleam/dynamic
import gleam/dynamic/decode
import gleam/string_tree.{type StringTree}
import serializer
import type_descriptor
import unrecognized

pub type FieldSpec(s, f) {
  FieldSpec(
    name: String,
    number: Int,
    doc: String,
    get: fn(s) -> f,
    set: fn(s, f) -> s,
    type_adapter: fn() -> serializer.TypeAdapter(f),
    recursive: Bool,
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

type StructAdapter(s) {
  StructAdapter(
    name: String,
    doc: String,
    fields: List(FieldAdapter(s)),
    get_unrecognized: fn(s) -> unrecognized.UnrecognizedFields(s),
    set_unrecognized: fn(s, unrecognized.UnrecognizedFields(s)) -> s,
  )
}

pub fn field_spec_to_field_adapter(spec: FieldSpec(s, f)) -> FieldAdapter(s) {
  case spec.recursive {
    False -> {
      let ta = spec.type_adapter()
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
    True ->
      FieldAdapter(
        name: spec.name,
        number: spec.number,
        doc: spec.doc,
        is_default: fn(s) { spec.type_adapter().is_default(spec.get(s)) },
        append_json: fn(s, tree, eol_indent) {
          spec.type_adapter().append_json(spec.get(s), tree, eol_indent)
        },
        decode_json: fn(d, s) {
          case decode.run(d, spec.type_adapter().decode_json) {
            Ok(f_val) -> Ok(spec.set(s, f_val))
            Error([decode.DecodeError(expected:, found:, ..), ..]) ->
              Error("expected " <> expected <> " but found " <> found)
            Error([]) -> Error("decode error")
          }
        },
        encode: fn(s, tree) { spec.type_adapter().encode(spec.get(s), tree) },
        decode: fn(bits, s, keep_unrecognized) {
          case spec.type_adapter().decode(bits, keep_unrecognized) {
            Ok(#(f_val, rest)) -> Ok(#(spec.set(s, f_val), rest))
            Error(e) -> Error(e)
          }
        },
        type_descriptor: fn() { spec.type_adapter().type_descriptor() },
      )
  }
}
// fn is_default(a: StructAdapter(s), s: s) -> Bool {
//   case a.get_unrecognized(s) {
//     Some(_) -> False
//     None -> list.all(a.fields, fn(f) { f.is_default(s) })
//   }
// }

// fn append_json(
//   a: StructAdapter(s),
//   s: s,
//   tree: string_tree.StringTree,
//   eol_indent: String,
// ) -> string_tree.StringTree {
//   case eol_indent {
//     "" -> append_dense_json(a, s, tree)
//     _ -> append_readable_json(a, s, tree, eol_indent)
//   }
// }

// fn decode_json(
//   a: StructAdapter(s),
//   d: dynamic.Dynamic,
//   s: s,
// ) -> Result(s, String) {
//   case decode.run(d, decode.list(decode.dynamic)) {
//     Ok(arr) -> from_dense_json(a, arr, s, False)
//     Error(_) ->
//       case decode.run(d, decode.dict(decode.string, decode.dynamic)) {
//         Ok(obj) -> from_readable_json(a, obj, s)
//         Error(_) -> Ok(s)
//       }
//   }
// }

// fn encode(
//   a: StructAdapter(s),
//   s: s,
//   tree: bytes_tree.BytesTree,
// ) -> bytes_tree.BytesTree {
//   let unrec = a.get_unrecognized(s)
//   let #(total_slot_count, recognized_slot_count, extra_bytes) = case unrec {
//     Some(u) -> {
//       let fmt = unrecognized.fields_data_format(u)
//       let vals = unrecognized.fields_data_values(u)
//       case fmt == unrecognized.BinaryBytes && bit_array.byte_size(vals) > 0 {
//         True -> {
//           let recognized = max_number_plus_one(a.fields)
//           #(unrecognized.fields_data_array_len(u), recognized, Some(vals))
//         }
//         False -> {
//           let c = get_slot_count(a.fields, s)
//           #(c, c, None)
//         }
//       }
//     }
//     None -> {
//       let c = get_slot_count(a.fields, s)
//       #(c, c, None)
//     }
//   }
//   let tree = encode_slot_count(total_slot_count, tree)
//   let tree = encode_slots_binary(a.fields, s, 0, recognized_slot_count, tree)
//   case extra_bytes {
//     Some(bytes) -> bytes_tree.append(tree, bytes)
//     None -> tree
//   }
// }

// fn decode(
//   a: StructAdapter(s),
//   bits: BitArray,
//   s: s,
//   keep_unrecognized: Bool,
// ) -> Result(#(s, BitArray), String) {
//   case bits {
//     <<wire, rest:bits>> ->
//       case wire {
//         0 | 246 -> Ok(#(s, rest))
//         _ ->
//           case decode_slot_count(wire, rest) {
//             Error(e) -> Error(e)
//             Ok(#(slot_count, rest2)) -> {
//               let recognized_count = max_number_plus_one(a.fields)
//               let slots_to_fill = int.min(slot_count, recognized_count)
//               case
//                 decode_slots(
//                   a.fields,
//                   s,
//                   0,
//                   slots_to_fill,
//                   rest2,
//                   keep_unrecognized,
//                 )
//               {
//                 Error(e) -> Error(e)
//                 Ok(#(s2, rest3)) -> {
//                   case slot_count > recognized_count {
//                     False -> Ok(#(s2, rest3))
//                     True -> {
//                       let extra = slot_count - recognized_count
//                       case keep_unrecognized {
//                         True ->
//                           capture_unrecognized_bytes(
//                             a,
//                             s2,
//                             slot_count,
//                             extra,
//                             rest3,
//                           )
//                         False ->
//                           case decode_utils.skip_n_values(extra, rest3) {
//                             Error(e) -> Error(e)
//                             Ok(remaining) -> Ok(#(s2, remaining))
//                           }
//                       }
//                     }
//                   }
//                 }
//               }
//             }
//           }
//       }
//     _ -> Error("unexpected end of input")
//   }
// }

// // =============================================================================
// // Dense JSON helpers
// // =============================================================================

// fn append_dense_json(
//   a: StructAdapter(s),
//   s: s,
//   tree: string_tree.StringTree,
// ) -> string_tree.StringTree {
//   let tree = string_tree.append(tree, "[")
//   let unrec = a.get_unrecognized(s)
//   let tree = case unrec {
//     Some(u) -> {
//       let fmt = unrecognized.fields_data_format(u)
//       let vals = unrecognized.fields_data_values(u)
//       case fmt == unrecognized.DenseJson && bit_array.byte_size(vals) > 0 {
//         True -> {
//           let recognized_count = max_number_plus_one(a.fields)
//           let tree = append_json_slots(a.fields, s, 0, recognized_count, tree)
//           let extra_str = case bit_array.to_string(vals) {
//             Ok(raw) ->
//               raw
//               |> string.trim
//               |> string.drop_start(1)
//               |> string.drop_end(1)
//               |> string.trim
//             Error(_) -> ""
//           }
//           case extra_str {
//             "" -> tree
//             _ -> {
//               let prefix = case recognized_count > 0 {
//                 True -> ","
//                 False -> ""
//               }
//               string_tree.append(tree, prefix <> extra_str)
//             }
//           }
//         }
//         False -> {
//           let slot_count = get_slot_count(a.fields, s)
//           append_json_slots(a.fields, s, 0, slot_count, tree)
//         }
//       }
//     }
//     None -> {
//       let slot_count = get_slot_count(a.fields, s)
//       append_json_slots(a.fields, s, 0, slot_count, tree)
//     }
//   }
//   string_tree.append(tree, "]")
// }

// fn append_readable_json(
//   a: StructAdapter(s),
//   s: s,
//   tree: string_tree.StringTree,
//   eol_indent: String,
// ) -> string_tree.StringTree {
//   let child_indent = eol_indent <> "  "
//   let tree = string_tree.append(tree, "{")
//   let #(tree, any) =
//     list.fold(a.fields, #(tree, False), fn(pair, f) {
//       let #(t, had_any) = pair
//       case f.is_default(s) {
//         True -> #(t, had_any)
//         False -> {
//           let t = case had_any {
//             True -> string_tree.append(t, ",")
//             False -> t
//           }
//           let t = string_tree.append(t, child_indent)
//           let t = string_tree.append(t, json.to_string(json.string(f.name)))
//           let t = string_tree.append(t, ": ")
//           let t = f.append_json(s, t, child_indent)
//           #(t, True)
//         }
//       }
//     })
//   let tree = case any {
//     True -> string_tree.append(tree, eol_indent)
//     False -> tree
//   }
//   string_tree.append(tree, "}")
// }

// fn append_json_slots(
//   fields: List(FieldAdapter(s)),
//   s: s,
//   i: Int,
//   count: Int,
//   tree: string_tree.StringTree,
// ) -> string_tree.StringTree {
//   case i >= count {
//     True -> tree
//     False -> {
//       let tree = case i > 0 {
//         True -> string_tree.append(tree, ",")
//         False -> tree
//       }
//       let tree = case find_field_by_number(fields, i) {
//         Some(f) -> f.append_json(s, tree, "")
//         None -> string_tree.append(tree, "0")
//       }
//       append_json_slots(fields, s, i + 1, count, tree)
//     }
//   }
// }

// // =============================================================================
// // JSON decode helpers
// // =============================================================================

// fn from_dense_json(
//   a: StructAdapter(s),
//   arr: List(dynamic.Dynamic),
//   s: s,
//   _keep_unrecognized: Bool,
// ) -> Result(s, String) {
//   let total_items = list.length(arr)
//   let recognized_count = max_number_plus_one(a.fields)
//   let num_to_fill = int.min(total_items, recognized_count)
//   list_fold_result(a.fields, s, fn(acc, f) {
//     case f.number < num_to_fill {
//       False -> Ok(acc)
//       True ->
//         case list_at(arr, f.number) {
//           None -> Ok(acc)
//           Some(elem) -> f.decode_json(elem, acc)
//         }
//     }
//   })
// }

// fn from_readable_json(
//   a: StructAdapter(s),
//   obj: dict.Dict(String, dynamic.Dynamic),
//   s: s,
// ) -> Result(s, String) {
//   list_fold_result(a.fields, s, fn(acc, f) {
//     case dict.get(obj, f.name) {
//       Error(_) -> Ok(acc)
//       Ok(v) -> f.decode_json(v, acc)
//     }
//   })
// }

// // =============================================================================
// // Binary encode helpers
// // =============================================================================

// fn encode_slot_count(n: Int, tree: bytes_tree.BytesTree) -> bytes_tree.BytesTree {
//   case n <= 3 {
//     True -> {
//       let header = 246 + n
//       bytes_tree.append(tree, <<header>>)
//     }
//     False ->
//       tree
//       |> bytes_tree.append(<<250>>)
//       |> bytes_tree.append(encode_uint32(n))
//   }
// }

// fn encode_uint32(n: Int) -> BitArray {
//   case n {
//     _ if n <= 231 -> <<n>>
//     _ if n <= 65_535 -> <<232, n:size(16)-little>>
//     _ -> <<233, n:size(32)-little>>
//   }
// }

// fn encode_slots_binary(
//   fields: List(FieldAdapter(s)),
//   s: s,
//   i: Int,
//   count: Int,
//   tree: bytes_tree.BytesTree,
// ) -> bytes_tree.BytesTree {
//   case i >= count {
//     True -> tree
//     False -> {
//       let tree = case find_field_by_number(fields, i) {
//         Some(f) -> f.encode(s, tree)
//         None -> bytes_tree.append(tree, <<0>>)
//       }
//       encode_slots_binary(fields, s, i + 1, count, tree)
//     }
//   }
// }

// // =============================================================================
// // Binary decode helpers
// // =============================================================================

// fn decode_slot_count(
//   wire: Int,
//   rest: BitArray,
// ) -> Result(#(Int, BitArray), String) {
//   case wire {
//     250 -> decode_utils.decode_number(rest)
//     247 | 248 | 249 -> Ok(#(wire - 246, rest))
//     _ -> Error("unexpected wire byte for struct: " <> int.to_string(wire))
//   }
// }

// fn decode_slots(
//   fields: List(FieldAdapter(s)),
//   s: s,
//   i: Int,
//   count: Int,
//   bits: BitArray,
//   keep_unrecognized: Bool,
// ) -> Result(#(s, BitArray), String) {
//   case i >= count {
//     True -> Ok(#(s, bits))
//     False ->
//       case find_field_by_number(fields, i) {
//         Some(f) ->
//           case f.decode(bits, s, keep_unrecognized) {
//             Error(e) -> Error(e)
//             Ok(#(new_s, rest)) ->
//               decode_slots(fields, new_s, i + 1, count, rest, keep_unrecognized)
//           }
//         None ->
//           case decode_utils.skip_value(bits) {
//             Error(e) -> Error(e)
//             Ok(rest) ->
//               decode_slots(fields, s, i + 1, count, rest, keep_unrecognized)
//           }
//       }
//   }
// }

// fn capture_unrecognized_bytes(
//   a: StructAdapter(s),
//   s: s,
//   total_slot_count: Int,
//   extra: Int,
//   rest3: BitArray,
// ) -> Result(#(s, BitArray), String) {
//   let before_size = bit_array.byte_size(rest3)
//   case decode_utils.skip_n_values(extra, rest3) {
//     Error(e) -> Error(e)
//     Ok(remaining) -> {
//       let consumed = before_size - bit_array.byte_size(remaining)
//       case rest3 {
//         <<captured:bytes-size(consumed), _:bits>> -> {
//           let new_s =
//             a.set_unrecognized(
//               s,
//               Some(unrecognized.fields_data_from_bytes(
//                 total_slot_count,
//                 captured,
//               )),
//             )
//           Ok(#(new_s, remaining))
//         }
//         _ -> Ok(#(s, remaining))
//       }
//     }
//   }
// }

// // =============================================================================
// // Utility helpers
// // =============================================================================

// fn get_slot_count(fields: List(FieldAdapter(s)), s: s) -> Int {
//   list.fold(fields, 0, fn(max_so_far, f) {
//     case f.is_default(s) {
//       True -> max_so_far
//       False -> int.max(max_so_far, f.number + 1)
//     }
//   })
// }

// fn max_number_plus_one(fields: List(FieldAdapter(s))) -> Int {
//   list.fold(fields, 0, fn(acc, f) { int.max(acc, f.number + 1) })
// }

// fn find_field_by_number(
//   fields: List(FieldAdapter(s)),
//   n: Int,
// ) -> Option(FieldAdapter(s)) {
//   case list.find(fields, fn(f) { f.number == n }) {
//     Ok(f) -> Some(f)
//     Error(_) -> None
//   }
// }

// fn list_fold_result(
//   lst: List(a),
//   acc: b,
//   f: fn(b, a) -> Result(b, String),
// ) -> Result(b, String) {
//   case lst {
//     [] -> Ok(acc)
//     [first, ..rest] ->
//       case f(acc, first) {
//         Error(e) -> Error(e)
//         Ok(new_acc) -> list_fold_result(rest, new_acc, f)
//       }
//   }
// }

// fn list_at(lst: List(a), i: Int) -> Option(a) {
//   case lst {
//     [] -> None
//     [first, ..rest] ->
//       case i {
//         0 -> Some(first)
//         _ -> list_at(rest, i - 1)
//       }
//   }
// }
