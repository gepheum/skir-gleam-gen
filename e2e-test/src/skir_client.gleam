////  ______                        _               _  _  _
////  |  _  \                      | |             | |(_)| |
////  | | | |  ___    _ __    ___  | |_    ___   __| | _ | |_
////  | | | | / _ \  | '_ \  / _ \ | __|  / _ \ / _` || || __|
////  | |/ / | (_) | | | | || (_) || |_  |  __/| (_| || || |_
////  |___/   \___/  |_| |_| \___/  \__|  \___| \__,_||_| \__|
////
//// Stub implementation of the Skir Gleam client library.
////
//// This module provides the types and functions that the Skir code generator
//// relies on at runtime. In a real project, this module would be provided by
//// the `skir_gleam_client` package instead of being written by hand.
////
//// Methods return dummy values here; the purpose of this file is to define
//// the correct API shape, not to implement the actual serialization logic.

import gleam/dict.{type Dict}
import gleam/option.{type Option, None, Some}
import tempo

// =============================================================================
// UnrecognizedFields
// =============================================================================

/// Holds field data encountered during deserialization that this client does
/// not recognise. Generated structs store this value so that re-serialising
/// them to JSON or bytes does not silently discard forward-compatible fields.
///
/// This is an implementation detail of the Skir runtime library. Set this
/// field to `no_unrecognized_fields()` whenever you construct a struct
/// manually; the runtime populates it automatically when deserialising.
pub opaque type UnrecognizedFields {
  UnrecognizedFields(data: List(#(Int, BitArray)))
}

/// Returns an empty `UnrecognizedFields` value.
/// Use this when constructing a Skir-generated struct manually.
pub fn no_unrecognized_fields() -> UnrecognizedFields {
  UnrecognizedFields(data: [])
}

// =============================================================================
// Serializer
// =============================================================================

/// A value that can serialize and deserialize values of type `a` to/from JSON
/// and binary formats.
pub opaque type Serializer(a) {
  Serializer(
    to_dense_json: fn(a) -> String,
    to_readable_json: fn(a) -> String,
    from_json: fn(String, Bool) -> Result(a, String),
    to_bytes: fn(a) -> BitArray,
    from_bytes: fn(BitArray, Bool) -> Result(a, String),
    type_descriptor: TypeDescriptor,
  )
}

/// Returns a stub serializer. The stub serializer returns empty/default values
/// and is used in this example project where real serialization is not
/// implemented.
pub fn stub_serializer() -> Serializer(a) {
  Serializer(
    to_dense_json: fn(_) { "[]" },
    to_readable_json: fn(_) { "{}" },
    from_json: fn(_, _) { Error("stub serializer") },
    to_bytes: fn(_) { <<>> },
    from_bytes: fn(_, _) { Error("stub serializer") },
    type_descriptor: StubTypeDescriptor,
  )
}

/// Serializes a value to dense (field-index-based) JSON.
/// Dense JSON is safe for persistent storage: renaming a field does not break
/// deserialization.
pub fn to_dense_json(serializer: Serializer(a), value: a) -> String {
  serializer.to_dense_json(value)
}

/// Serializes a value to readable (field-name-based, indented) JSON.
/// Use this for debugging; prefer `to_dense_json` for storage.
pub fn to_readable_json(serializer: Serializer(a), value: a) -> String {
  serializer.to_readable_json(value)
}

/// Deserializes a value from a JSON string. Accepts both dense and readable
/// JSON. Unrecognized fields are dropped.
pub fn from_json(
  serializer: Serializer(a),
  json: String,
) -> Result(a, String) {
  serializer.from_json(json, False)
}

/// Deserializes a value from a JSON string.
/// When `keep_unrecognized_values` is `True`, field data that this client
/// does not recognise is preserved in `unrecognized_fields_` so that
/// re-serializing the value does not silently discard forward-compatible
/// fields.
pub fn from_json_with_options(
  serializer: Serializer(a),
  json: String,
  keep_unrecognized_values keep_unrecognized_values: Bool,
) -> Result(a, String) {
  serializer.from_json(json, keep_unrecognized_values)
}

/// Serializes a value to a compact binary format.
pub fn to_bytes(serializer: Serializer(a), value: a) -> BitArray {
  serializer.to_bytes(value)
}

/// Deserializes a value from binary format. Unrecognized fields are dropped.
pub fn from_bytes(
  serializer: Serializer(a),
  bytes: BitArray,
) -> Result(a, String) {
  serializer.from_bytes(bytes, False)
}

/// Deserializes a value from binary format.
/// When `keep_unrecognized_values` is `True`, field data that this client
/// does not recognise is preserved in `unrecognized_fields_`.
pub fn from_bytes_with_options(
  serializer: Serializer(a),
  bytes: BitArray,
  keep_unrecognized_values keep_unrecognized_values: Bool,
) -> Result(a, String) {
  serializer.from_bytes(bytes, keep_unrecognized_values)
}

/// Returns the TypeDescriptor for the type this serializer handles.
pub fn type_descriptor(serializer: Serializer(a)) -> TypeDescriptor {
  serializer.type_descriptor
}

// =============================================================================
// Primitive Serializers
// =============================================================================

/// Returns the serializer for Bool values.
pub fn bool_serializer() -> Serializer(Bool) {
  stub_serializer()
}

/// Returns the serializer for Int (int32) values.
pub fn int32_serializer() -> Serializer(Int) {
  stub_serializer()
}

/// Returns the serializer for Int (int64) values.
pub fn int64_serializer() -> Serializer(Int) {
  stub_serializer()
}

/// Returns the serializer for Int (hash64) values.
pub fn hash64_serializer() -> Serializer(Int) {
  stub_serializer()
}

/// Returns the serializer for Float (float32) values.
pub fn float32_serializer() -> Serializer(Float) {
  stub_serializer()
}

/// Returns the serializer for Float (float64) values.
pub fn float64_serializer() -> Serializer(Float) {
  stub_serializer()
}

/// Returns the serializer for String values.
pub fn string_serializer() -> Serializer(String) {
  stub_serializer()
}

/// Returns the serializer for BitArray (bytes) values.
pub fn bytes_serializer() -> Serializer(BitArray) {
  stub_serializer()
}

/// Returns the serializer for tempo.DateTime values.
pub fn datetime_serializer() -> Serializer(tempo.DateTime) {
  stub_serializer()
}

// =============================================================================
// Composite Serializers
// =============================================================================

/// Returns a serializer for Option(a) values.
pub fn optional_serializer(
  item_serializer: Serializer(a),
) -> Serializer(Option(a)) {
  let _ = item_serializer
  stub_serializer()
}

/// Returns a serializer for List(a) values.
pub fn list_serializer(
  item_serializer: Serializer(a),
) -> Serializer(List(a)) {
  let _ = item_serializer
  stub_serializer()
}

// =============================================================================
// KeyedList
// =============================================================================

/// An immutable list with O(1) lookup by a key field.
///
/// The index is built lazily on the first call to `keyed_list_find` and cached
/// for subsequent calls.
pub opaque type KeyedList(item) {
  KeyedList(items: List(item), index: Dict(Int, item))
}

/// Returns an empty KeyedList.
pub fn empty_keyed_list() -> KeyedList(a) {
  KeyedList(items: [], index: dict.new())
}

/// Constructs a KeyedList from a list of items and a key extractor function.
pub fn keyed_list_from_list(
  items: List(a),
  get_key: fn(a) -> Int,
) -> KeyedList(a) {
  let index =
    items
    |> list_fold(dict.new(), fn(acc, item) {
      dict.insert(acc, get_key(item), item)
    })
  KeyedList(items:, index:)
}

/// Returns all items in the KeyedList as a plain List.
pub fn keyed_list_to_list(keyed: KeyedList(a)) -> List(a) {
  keyed.items
}

/// Finds an item by its Int key. Returns `Some(item)` if found, `None`
/// otherwise.
/// The first call is O(N) to build the index; subsequent calls are O(1).
/// If multiple items share the same key, the last one wins.
pub fn keyed_list_find(keyed: KeyedList(a), key: Int) -> Option(a) {
  dict.get(keyed.index, key)
  |> result_to_option
}

// =============================================================================
// Method
// =============================================================================

/// Metadata for a Skir RPC method.
pub type Method(request, response) {
  Method(
    /// The method name as declared in the .skir file.
    name: String,
    /// The stable numeric identifier of the method.
    number: Int,
    /// The documentation comment from the .skir file.
    doc: String,
    /// Serializer for request values.
    request_serializer: Serializer(request),
    /// Serializer for response values.
    response_serializer: Serializer(response),
  )
}

// =============================================================================
// TypeDescriptor (reflection)
// =============================================================================

/// Describes the runtime shape of a Skir type.
pub type TypeDescriptor {
  StubTypeDescriptor
  StructDescriptor(fields: List(FieldDescriptor))
  EnumDescriptor(variants: List(VariantDescriptor))
}

/// Describes a single field of a Skir struct.
pub type FieldDescriptor {
  FieldDescriptor(name: String, number: Int)
}

/// Describes a single variant of a Skir enum.
pub type VariantDescriptor {
  VariantDescriptor(name: String, number: Int)
}

/// Serializes a TypeDescriptor to a JSON string.
pub fn type_descriptor_to_json(td: TypeDescriptor) -> String {
  let _ = td
  "{}"
}

/// Parses a TypeDescriptor from a JSON string.
pub fn type_descriptor_from_json(json: String) -> Result(TypeDescriptor, String) {
  let _ = json
  Ok(StubTypeDescriptor)
}

// =============================================================================
// Internal helpers (not part of the public Skir client API)
// =============================================================================

fn list_fold(list: List(a), acc: b, f: fn(b, a) -> b) -> b {
  case list {
    [] -> acc
    [first, ..rest] -> list_fold(rest, f(acc, first), f)
  }
}

fn result_to_option(result: Result(a, b)) -> Option(a) {
  case result {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}
