import gleam/bit_array
import gleam/bytes_tree.{type BytesTree}
import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/string_tree.{type StringTree}
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
    append_json: fn(a, StringTree, String) -> StringTree,
    /// Returns a JSON decoder. When the argument is `Keep`, the decoder
    /// preserves unrecognized fields/variants. When `Drop`, it discards them.
    /// For primitive types the argument is ignored.
    decode_json: fn(UnrecognizedValues) -> Decoder(a),
    encode: fn(a, BytesTree) -> BytesTree,
    decode: fn(BitArray, UnrecognizedValues) -> Result(#(a, BitArray), String),
    type_descriptor: fn() -> TypeDescriptor,
  )
}

/// Constructs a `TypeAdapter` for type `a`.
/// Used internally by the Skir client library and by generated code.
pub fn make_type_adapter(
  is_default is_default: fn(a) -> Bool,
  append_json append_json: fn(a, StringTree, String) -> StringTree,
  decode_json decode_json: fn(UnrecognizedValues) -> Decoder(a),
  encode encode: fn(a, BytesTree) -> BytesTree,
  decode decode: fn(BitArray, UnrecognizedValues) ->
    Result(#(a, BitArray), String),
  type_descriptor type_descriptor: fn() -> TypeDescriptor,
) -> TypeAdapter(a) {
  TypeAdapter(
    is_default:,
    append_json:,
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

/// Returns `True` if `value` is the default value for the type.
pub fn is_default(serializer: Serializer(a), value: a) -> Bool {
  serializer.internal_adapter.is_default(value)
}

// =============================================================================
// Core serialization API
// =============================================================================

/// Serializes a value to dense (field-index-based) JSON.
/// Dense JSON is safe for persistent storage: renaming a field does not break
/// deserialization.
pub fn to_dense_json(serializer: Serializer(a), value: a) -> String {
  serializer.internal_adapter.append_json(value, string_tree.new(), "")
  |> string_tree.to_string()
}

/// Serializes a value to readable (field-name-based, indented) JSON.
/// Use this for debugging; prefer `to_dense_json` for storage.
pub fn to_readable_json(serializer: Serializer(a), value: a) -> String {
  serializer.internal_adapter.append_json(value, string_tree.new(), "\n")
  |> string_tree.to_string()
}

/// Deserializes a value from a JSON string. Accepts both dense and readable
/// JSON. Unrecognized fields are dropped.
pub fn from_json(serializer: Serializer(a), json: String) -> Result(a, String) {
  case
    json.parse(from: json, using: serializer.internal_adapter.decode_json(Drop))
  {
    Ok(v) -> Ok(v)
    Error(e) -> Error(json_decode_error_to_string(e))
  }
}

/// Deserializes a value from a JSON string.
/// When `keep_unrecognized_values` is `Keep`, field data that this client
/// does not recognise is preserved in `unrecognized_fields_` so that
/// re-serializing the value does not silently discard forward-compatible
/// fields.
pub fn from_json_with_options(
  serializer: Serializer(a),
  json: String,
  keep_unrecognized_values keep_unrecognized_values: UnrecognizedValues,
) -> Result(a, String) {
  case
    json.parse(
      from: json,
      using: serializer.internal_adapter.decode_json(keep_unrecognized_values),
    )
  {
    Ok(v) -> Ok(v)
    Error(e) -> Error(json_decode_error_to_string(e))
  }
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
          case
            json.parse(
              from: s,
              using: serializer.internal_adapter.decode_json(
                keep_unrecognized_values,
              ),
            )
          {
            Ok(v) -> Ok(v)
            Error(e) -> Error(json_decode_error_to_string(e))
          }
        Error(_) -> Error("invalid bytes: not skir binary and not valid UTF-8")
      }
  }
}

/// Returns the TypeDescriptor for the type this serializer handles.
pub fn type_descriptor(serializer: Serializer(a)) -> TypeDescriptor {
  serializer.internal_adapter.type_descriptor()
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
