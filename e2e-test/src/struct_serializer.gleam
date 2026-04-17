import gleam/bytes_tree
import gleam/string_tree
import serializer
import type_descriptor

pub type Type(t) {
  Adapter(serializer.TypeAdapter(t))
  Serializer(fn() -> serializer.Serializer(t))
}

pub type FieldAdapter(s, b) {
  FieldAdapter(
    name: String,
    doc: String,
    is_default: fn(s) -> Bool,
    append_json: fn(s, string_tree.StringTree, String) -> string_tree.StringTree,
    decode_json: Decoder(a),
    encode: fn(s, bytes_tree.BytesTree) -> bytes_tree.BytesTree,
    decode: fn(BitArray, Bool) -> Result(#(s, BitArray), String),
    type_descriptor: type_descriptor.TypeDescriptor,
  )
}
