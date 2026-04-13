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

import gleam/bytes_tree.{type BytesTree}
import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/option.{type Option}
import gleam/string_tree.{type StringTree}
import gleam/time/timestamp.{type Timestamp}
import serializer
import serializers
import type_descriptor.{type TypeDescriptor}

// =============================================================================
// Re-exported types from serializer
// =============================================================================

pub type TypeAdapter(a) =
  serializer.TypeAdapter(a)

pub type Serializer(a) =
  serializer.Serializer(a)

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

// Re-export TypeDescriptor and related types so callers can
// import them from this module.
pub type PrimitiveType =
  type_descriptor.PrimitiveType

pub type StructDescriptor =
  type_descriptor.StructDescriptor

pub type StructField =
  type_descriptor.StructField

pub type EnumDescriptor =
  type_descriptor.EnumDescriptor

pub type EnumVariant =
  type_descriptor.EnumVariant

// =============================================================================
// TypeAdapter / Serializer construction
// =============================================================================

/// Constructs a `TypeAdapter` for type `a`.
/// Used internally by the Skir client library and by generated code.
pub fn make_type_adapter(
  append_json append_json: fn(a, StringTree, String) -> StringTree,
  json_decoder json_decoder: Decoder(a),
  encode encode: fn(a, BytesTree) -> BytesTree,
  decode decode: fn(BitArray, Bool) -> Result(#(a, BitArray), String),
  type_descriptor type_descriptor: TypeDescriptor,
) -> TypeAdapter(a) {
  serializer.make_type_adapter(
    append_json:,
    json_decoder:,
    encode:,
    decode:,
    type_descriptor:,
  )
}

/// Constructs a `Serializer` from a `TypeAdapter`.
/// Used internally by the Skir client library and by generated code.
pub fn make_serializer(adapter: TypeAdapter(a)) -> Serializer(a) {
  serializer.make_serializer(adapter)
}

/// Returns a stub serializer.
pub fn stub_serializer() -> Serializer(a) {
  serializer.stub_serializer()
}

// =============================================================================
// Core serialization API
// =============================================================================

/// Serializes a value to dense (field-index-based) JSON.
pub fn to_dense_json(serializer: Serializer(a), value: a) -> String {
  serializer.to_dense_json(serializer, value)
}

/// Serializes a value to readable (field-name-based, indented) JSON.
pub fn to_readable_json(serializer: Serializer(a), value: a) -> String {
  serializer.to_readable_json(serializer, value)
}

/// Deserializes a value from a JSON string.
pub fn from_json(serializer: Serializer(a), json: String) -> Result(a, String) {
  serializer.from_json(serializer, json)
}

/// Deserializes a value from a JSON string with options.
pub fn from_json_with_options(
  serializer: Serializer(a),
  json: String,
  keep_unrecognized_values keep_unrecognized_values: Bool,
) -> Result(a, String) {
  serializer.from_json_with_options(serializer, json, keep_unrecognized_values:)
}

/// Serializes a value to a compact binary format.
pub fn to_bytes(serializer: Serializer(a), value: a) -> BitArray {
  serializer.to_bytes(serializer, value)
}

/// Deserializes a value from binary format.
pub fn from_bytes(
  serializer: Serializer(a),
  bytes: BitArray,
) -> Result(a, String) {
  serializer.from_bytes(serializer, bytes)
}

/// Deserializes a value from binary format with options.
pub fn from_bytes_with_options(
  serializer: Serializer(a),
  bytes: BitArray,
  keep_unrecognized_values keep_unrecognized_values: Bool,
) -> Result(a, String) {
  serializer.from_bytes_with_options(
    serializer,
    bytes,
    keep_unrecognized_values:,
  )
}

/// Returns the TypeDescriptor for the type this serializer handles.
pub fn type_descriptor(serializer: Serializer(a)) -> TypeDescriptor {
  serializer.type_descriptor(serializer)
}

// =============================================================================
// Primitive Serializers
// =============================================================================

/// Returns the serializer for Bool values.
pub fn bool_serializer() -> Serializer(Bool) {
  serializers.bool_serializer()
}

/// Returns the serializer for Int (int32) values.
pub fn int32_serializer() -> Serializer(Int) {
  serializers.int32_serializer()
}

/// Returns the serializer for Int (int64) values.
pub fn int64_serializer() -> Serializer(Int) {
  serializers.int64_serializer()
}

/// Returns the serializer for Int (hash64) values.
pub fn hash64_serializer() -> Serializer(Int) {
  serializers.hash64_serializer()
}

/// Returns the serializer for Float (float32) values.
pub fn float32_serializer() -> Serializer(Float) {
  serializers.float32_serializer()
}

/// Returns the serializer for Float (float64) values.
pub fn float64_serializer() -> Serializer(Float) {
  serializers.float64_serializer()
}

/// Returns the serializer for String values.
pub fn string_serializer() -> Serializer(String) {
  serializers.string_serializer()
}

/// Returns the serializer for BitArray (bytes) values.
pub fn bytes_serializer() -> Serializer(BitArray) {
  serializers.bytes_serializer()
}

/// Returns the serializer for Timestamp values.
pub fn timestamp_serializer() -> Serializer(Timestamp) {
  serializers.timestamp_serializer()
}

// =============================================================================
// Composite Serializers
// =============================================================================

/// Returns a serializer for Option(a) values.
pub fn optional_serializer(
  item_serializer: Serializer(a),
) -> Serializer(Option(a)) {
  serializers.optional_serializer(item_serializer)
}

/// Returns a serializer for List(a) values.
pub fn list_serializer(item_serializer: Serializer(a)) -> Serializer(List(a)) {
  serializers.list_serializer(item_serializer)
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

/// Serializes a TypeDescriptor to a JSON string.
pub fn type_descriptor_to_json(td: TypeDescriptor) -> String {
  type_descriptor.type_descriptor_to_json(td)
}

/// Parses a TypeDescriptor from a JSON string.
pub fn type_descriptor_from_json(json: String) -> Result(TypeDescriptor, String) {
  type_descriptor.type_descriptor_from_json(json)
}

// =============================================================================
// Internal helpers
// =============================================================================

fn list_fold(list: List(a), acc: b, f: fn(b, a) -> b) -> b {
  case list {
    [] -> acc
    [first, ..rest] -> list_fold(rest, f(acc, first), f)
  }
}

fn result_to_option(result: Result(a, b)) -> Option(a) {
  case result {
    Ok(value) -> option.Some(value)
    Error(_) -> option.None
  }
}
