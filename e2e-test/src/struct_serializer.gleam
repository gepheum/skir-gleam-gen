import gleam/bytes_tree
import gleam/dynamic
import gleam/string_tree
import type_descriptor

pub type FieldAdapter(s) {
  FieldAdapter(
    name: String,
    doc: String,
    is_default: fn(s) -> Bool,
    append_json: fn(s, string_tree.StringTree, String) -> string_tree.StringTree,
    decode_json: fn(dynamic.Dynamic, s) -> Result(s, String),
    encode: fn(s, bytes_tree.BytesTree) -> bytes_tree.BytesTree,
    decode: fn(BitArray, s, Bool) -> Result(#(s, BitArray), String),
    type_descriptor: type_descriptor.TypeDescriptor,
  )
}

pub type StructAdapter(s) {
  StructAdapter(
    name: String,
    doc: String,
    fields: List(FieldAdapter(s)),
    //
  )
}

fn is_default(a: StructAdapter(s), s: s) -> Bool {
  todo
}

fn append_json(
  a: StructAdapter(s),
  s: s,
  tree: string_tree.StringTree,
  eol_indent: String,
) -> string_tree.StringTree {
  todo
}

fn decode_json(
  a: StructAdapter(s),
  d: dynamic.Dynamic,
  s: s,
) -> Result(s, String) {
  todo
}

fn encode(
  a: StructAdapter(s),
  s: s,
  tree: bytes_tree.BytesTree,
) -> bytes_tree.BytesTree {
  todo
}

fn decode(
  a: StructAdapter(s),
  bits: BitArray,
  s: s,
  keep_unrecognized: Bool,
) -> Result(#(s, BitArray), String) {
  todo
}
