import gleam/bytes_tree.{type BytesTree}
import gleam/dynamic/decode.{type Decoder}
import gleam/json
import gleam/option.{type Option}
import internal/serializers
import serializer
import timestamp
import type_descriptor.{type TypeDescriptor}

// =============================================================================
// Re-exported types from serializer
// =============================================================================

pub type TypeAdapter(a) =
  serializer.TypeAdapter(a)

pub type Serializer(a) =
  serializer.Serializer(a)

pub type UnrecognizedValues =
  serializer.UnrecognizedValues

/// Preserve unrecognized fields/variants for round-tripping.
pub const keep_unrecognized: UnrecognizedValues = serializer.Keep

/// Discard unrecognized fields/variants.
pub const drop_unrecognized: UnrecognizedValues = serializer.Drop

// Re-export TypeDescriptor and related types so callers can
// import them from this module.
pub type PrimitiveType =
  type_descriptor.PrimitiveType

pub type TypeSignature =
  type_descriptor.TypeSignature

pub type RecordDescriptor =
  type_descriptor.RecordDescriptor

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
  is_default is_default: fn(a) -> Bool,
  to_json to_json: fn(a, Bool) -> json.Json,
  decode_json decode_json: fn(UnrecognizedValues) -> Decoder(a),
  encode encode: fn(a, BytesTree) -> BytesTree,
  decode decode: fn(BitArray, UnrecognizedValues) ->
    Result(#(a, BitArray), String),
  type_descriptor type_descriptor: fn() -> TypeDescriptor,
) -> TypeAdapter(a) {
  serializer.make_type_adapter(
    is_default:,
    to_json:,
    decode_json:,
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

// =============================================================================
// Core serialization API
// =============================================================================

/// Serializes a value to dense (field-index-based) JSON value.
pub fn to_dense_json(serializer: Serializer(a), value: a) -> json.Json {
  serializer.to_dense_json(serializer, value)
}

/// Serializes a value to dense (field-index-based) JSON code.
pub fn to_dense_json_code(serializer: Serializer(a), value: a) -> String {
  serializer.to_dense_json_code(serializer, value)
}

/// Serializes a value to readable (field-name-based) JSON value.
pub fn to_readable_json(serializer: Serializer(a), value: a) -> json.Json {
  serializer.to_readable_json(serializer, value)
}

/// Serializes a value to readable, 2-space-indented JSON code.
pub fn to_readable_json_code(serializer: Serializer(a), value: a) -> String {
  serializer.to_readable_json_code(serializer, value)
}

/// Deserializes a value from a JSON code string.
pub fn from_json_code(
  serializer: Serializer(a),
  json: String,
) -> Result(a, String) {
  serializer.from_json_code(serializer, json)
}

/// Deserializes a value from a JSON code string with options.
pub fn from_json_code_with_options(
  serializer: Serializer(a),
  json: String,
  keep_unrecognized_values keep_unrecognized_values: UnrecognizedValues,
) -> Result(a, String) {
  serializer.from_json_code_with_options(
    serializer,
    json,
    keep_unrecognized_values:,
  )
}

pub fn json_decoder(serializer: Serializer(a)) -> Decoder(a) {
  serializer.json_decoder(serializer)
}

pub fn json_decoder_with_options(
  serializer: Serializer(a),
  keep_unrecognized_values keep_unrecognized_values: UnrecognizedValues,
) -> Decoder(a) {
  serializer.json_decoder_with_options(serializer, keep_unrecognized_values:)
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
  keep_unrecognized_values keep_unrecognized_values: UnrecognizedValues,
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

/// Returns `True` if `value` is the default value for the type.
pub fn is_default(serializer: Serializer(a), value: a) -> Bool {
  serializer.is_default(serializer, value)
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
pub fn timestamp_serializer() -> Serializer(timestamp.Timestamp) {
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

// =============================================================================
// Recursive wrapper
// =============================================================================

/// Wraps a hard-recursive struct field value.
///
/// `Default` should be treated the same as the default value of `a`.
pub type Recursive(a) {
  /// Treat this like the default value of `a`.
  Default
  Some(a)
}

/// Returns a serializer for List(a) values.
pub fn list_serializer(item_serializer: Serializer(a)) -> Serializer(List(a)) {
  serializers.list_serializer(item_serializer)
}

/// Returns a serializer for List(a) values where a key extractor is provided.
pub fn keyed_list_serializer(
  item_serializer: Serializer(a),
  key_extractor: String,
) -> Serializer(List(a)) {
  serializers.keyed_list_serializer(item_serializer, key_extractor)
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
// TypeSignature constructors
// (Used by generated code — Gleam can't access enum constructors through
// qualified names, so we provide wrapper functions.)
// =============================================================================

pub fn type_sig_primitive(p: PrimitiveType) -> TypeSignature {
  type_descriptor.Primitive(p)
}

pub fn type_sig_optional(inner: TypeSignature) -> TypeSignature {
  type_descriptor.Optional(inner)
}

pub fn type_sig_array(
  item: TypeSignature,
  key_extractor: String,
) -> TypeSignature {
  type_descriptor.Array(item, key_extractor)
}

pub fn type_sig_record(id: String) -> TypeSignature {
  type_descriptor.Record(id)
}

pub fn prim_bool() -> PrimitiveType {
  type_descriptor.Bool
}

pub fn prim_int32() -> PrimitiveType {
  type_descriptor.Int32
}

pub fn prim_int64() -> PrimitiveType {
  type_descriptor.Int64
}

pub fn prim_hash64() -> PrimitiveType {
  type_descriptor.Hash64
}

pub fn prim_float32() -> PrimitiveType {
  type_descriptor.Float32
}

pub fn prim_float64() -> PrimitiveType {
  type_descriptor.Float64
}

pub fn prim_timestamp() -> PrimitiveType {
  type_descriptor.Timestamp
}

pub fn prim_string() -> PrimitiveType {
  type_descriptor.StringType
}

pub fn prim_bytes() -> PrimitiveType {
  type_descriptor.Bytes
}


