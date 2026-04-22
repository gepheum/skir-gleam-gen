import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string_tree
import internal/json_utils
import type_descriptor.{type TypeDescriptor}

// =============================================================================
// UnrecognizedValues
// =============================================================================

/// Controls whether unrecognized fields/variants encountered during
/// deserialization are preserved for round-tripping.
pub type UnrecognizedValues {
  /// Preserve unrecognized fields/variants so they survive a round-trip.
  Keep
  /// Discard unrecognized fields/variants.
  Drop
}

// =============================================================================
// TypeAdapter
// =============================================================================

/// An internal adapter that provides the type-specific logic for serialization
/// and deserialization. Used by `Serializer`.
pub type TypeAdapter(a) {
  TypeAdapter(
    is_default: fn(a) -> Bool,
    to_json: fn(a, Bool) -> json.Json,
    to_readable_json_code: fn(a, String) -> string_tree.StringTree,
    decode_json: fn(UnrecognizedValues) -> decode.Decoder(a),
    encode: fn(a, BytesTree) -> BytesTree,
    decode: fn(BitArray, UnrecognizedValues) -> Result(#(a, BitArray), String),
    type_descriptor: fn() -> TypeDescriptor,
  )
}

/// Constructs a `TypeAdapter` for type `a`.
/// Used internally by the Skir client library and by generated code.
pub fn make_type_adapter(
  is_default is_default: fn(a) -> Bool,
  to_json to_json: fn(a, Bool) -> json.Json,
  to_readable_json_code to_readable_json_code: fn(a, String) ->
    string_tree.StringTree,
  decode_json decode_json: fn(UnrecognizedValues) -> decode.Decoder(a),
  encode encode: fn(a, BytesTree) -> BytesTree,
  decode decode: fn(BitArray, UnrecognizedValues) ->
    Result(#(a, BitArray), String),
  type_descriptor type_descriptor: fn() -> TypeDescriptor,
) -> TypeAdapter(a) {
  TypeAdapter(
    is_default:,
    to_json:,
    to_readable_json_code:,
    decode_json:,
    encode:,
    decode:,
    type_descriptor:,
  )
}

// =============================================================================
// Serializer
// =============================================================================

/// A value that can serialize and deserialize values of type `a` to/from JSON
/// and binary formats.
pub type Serializer(a) {
  Serializer(internal_adapter: TypeAdapter(a))
}

/// Constructs a `Serializer` from a `TypeAdapter`.
pub fn make_serializer(adapter: TypeAdapter(a)) -> Serializer(a) {
  Serializer(internal_adapter: adapter)
}

// =============================================================================
// Core serialization API
// =============================================================================

/// Serializes a value to dense (field-index-based) JSON value.
pub fn to_dense_json(serializer: Serializer(a), value: a) -> json.Json {
  serializer.internal_adapter.to_json(value, False)
}

/// Serializes a value to dense (field-index-based) JSON code.
/// Dense JSON is safe for persistent storage: renaming a field does not break
/// deserialization.
pub fn to_dense_json_code(serializer: Serializer(a), value: a) -> String {
  serializer.internal_adapter.to_json(value, False)
  |> json.to_string()
}

/// Serializes a value to readable (field-name-based) JSON value.
pub fn to_readable_json(serializer: Serializer(a), value: a) -> json.Json {
  serializer.internal_adapter.to_json(value, True)
}

/// Serializes a value to readable (field-name-based, indented) JSON code.
/// Uses 2-space indentation.
pub fn to_readable_json_code(serializer: Serializer(a), value: a) -> String {
  serializer.internal_adapter.to_readable_json_code(value, "\n")
  |> string_tree.to_string
}

/// Deserializes a value from a JSON string. Accepts both dense and readable
/// JSON. Unrecognized fields are dropped.
pub fn from_json_code(
  serializer: Serializer(a),
  json_code: String,
) -> Result(a, String) {
  from_json_code_with_options(serializer, json_code, Drop)
}

/// Deserializes a value from a JSON string.
/// When `keep_unrecognized_values` is `Keep`, field data that this client
/// does not recognise is preserved in `unrecognized_fields_` so that
/// re-serializing the value does not silently discard forward-compatible
/// fields.
pub fn from_json_code_with_options(
  serializer: Serializer(a),
  json_code: String,
  keep_unrecognized_values keep_unrecognized_values: UnrecognizedValues,
) -> Result(a, String) {
  use d <- result.try(parse_json_code_to_dynamic(json_code))
  decode.run(
    d,
    serializer.internal_adapter.decode_json(keep_unrecognized_values),
  )
  |> result.map_error(json_utils.decode_errors_to_string)
}

/// Returns a JSON decoder for this serializer (Drop mode).
pub fn json_decoder(serializer: Serializer(a)) -> decode.Decoder(a) {
  json_decoder_with_options(serializer, Drop)
}

/// Returns a JSON decoder for this serializer with configurable keep/drop mode.
pub fn json_decoder_with_options(
  serializer: Serializer(a),
  keep_unrecognized_values keep_unrecognized_values: UnrecognizedValues,
) -> decode.Decoder(a) {
  serializer.internal_adapter.decode_json(keep_unrecognized_values)
}

/// Serializes a value to a compact binary format.
/// The binary format uses the `"skir"` magic prefix followed by the encoded
/// payload produced by the adapter.
pub fn to_bytes(serializer: Serializer(a), value: a) -> BitArray {
  bytes_tree.from_string("skir")
  |> serializer.internal_adapter.encode(value, _)
  |> bytes_tree.to_bit_array()
}

/// Deserializes a value from binary format. Unrecognized fields are dropped.
pub fn from_bytes(
  serializer: Serializer(a),
  bytes: BitArray,
) -> Result(a, String) {
  from_bytes_with_options(serializer, bytes, Drop)
}

/// Deserializes a value from binary format.
/// When `keep_unrecognized_values` is `Keep`, field data that this client
/// does not recognise is preserved in `unrecognized_fields_`.
pub fn from_bytes_with_options(
  serializer: Serializer(a),
  bytes: BitArray,
  keep_unrecognized_values keep_unrecognized_values: UnrecognizedValues,
) -> Result(a, String) {
  case bytes {
    <<115, 107, 105, 114, rest:bits>> ->
      case serializer.internal_adapter.decode(rest, keep_unrecognized_values) {
        Ok(#(value, _)) -> Ok(value)
        Error(e) -> Error(e)
      }
    _ ->
      case bit_array.to_string(bytes) {
        Ok(s) ->
          from_json_code_with_options(serializer, s, keep_unrecognized_values:)
        Error(_) -> Error("invalid bytes: not skir binary and not valid UTF-8")
      }
  }
}

/// Returns the TypeDescriptor for the type this serializer handles.
pub fn type_descriptor(serializer: Serializer(a)) -> TypeDescriptor {
  serializer.internal_adapter.type_descriptor()
}

/// Builds readable JSON array code from already-rendered readable item trees.
pub fn readable_json_array(
  items: List(string_tree.StringTree),
  eol_indent: String,
) -> string_tree.StringTree {
  case items {
    [] -> string_tree.from_string("[]")
    _ -> {
      let child_indent = eol_indent <> "  "
      let indented_items =
        list.map(items, fn(item) {
          string_tree.concat([
            string_tree.from_string(child_indent),
            item,
          ])
        })
      string_tree.concat([
        string_tree.from_string("["),
        string_tree.join(indented_items, ","),
        string_tree.from_string(eol_indent <> "]"),
      ])
    }
  }
}

/// Builds readable JSON object code from key/value readable trees.
pub fn readable_json_object(
  fields: List(#(String, string_tree.StringTree)),
  eol_indent: String,
) -> string_tree.StringTree {
  case fields {
    [] -> string_tree.from_string("{}")
    _ -> {
      let child_indent = eol_indent <> "  "
      let lines =
        list.map(fields, fn(field) {
          let #(name, value_tree) = field
          string_tree.concat([
            string_tree.from_string(child_indent),
            json.to_string_tree(json.string(name)),
            string_tree.from_string(": "),
            value_tree,
          ])
        })
      string_tree.concat([
        string_tree.from_string("{"),
        string_tree.join(lines, ","),
        string_tree.from_string(eol_indent <> "}"),
      ])
    }
  }
}

// =============================================================================
// Internal helpers
// =============================================================================

fn json_decode_error_to_string(e: json.DecodeError) -> String {
  case e {
    json.UnexpectedEndOfInput -> "unexpected end of JSON input"
    json.UnexpectedByte(b) -> "unexpected byte in JSON: " <> b
    json.UnexpectedSequence(s) -> "unexpected sequence in JSON: " <> s
    json.UnableToDecode(_) -> "unable to decode JSON value"
  }
}

fn parse_json_code_to_dynamic(
  json_code: String,
) -> Result(dynamic.Dynamic, String) {
  case json.parse(from: json_code, using: decode.dynamic) {
    Ok(d) -> Ok(d)
    Error(e) -> Error(json_decode_error_to_string(e))
  }
}
