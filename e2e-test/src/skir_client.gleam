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

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import tempo
import type_descriptor.{type TypeDescriptor}

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
// TypeAdapter
// =============================================================================

/// An internal adapter that provides the type-specific logic for serialization
/// and deserialization. Used by `Serializer`.
pub opaque type TypeAdapter(a) {
  TypeAdapter(
    to_dense_json: fn(a) -> String,
    to_readable_json: fn(a) -> String,
    from_json: fn(String, Bool) -> Result(a, String),
    encode: fn(a) -> BitArray,
    decode: fn(BitArray, Bool) -> Result(a, String),
    type_descriptor: TypeDescriptor,
  )
}

/// Constructs a `TypeAdapter` for type `a`.
/// Used internally by the Skir client library and by generated code.
pub fn make_type_adapter(
  to_dense_json to_dense_json: fn(a) -> String,
  to_readable_json to_readable_json: fn(a) -> String,
  from_json from_json: fn(String, Bool) -> Result(a, String),
  encode encode: fn(a) -> BitArray,
  decode decode: fn(BitArray, Bool) -> Result(a, String),
  type_descriptor type_descriptor: TypeDescriptor,
) -> TypeAdapter(a) {
  TypeAdapter(
    to_dense_json:,
    to_readable_json:,
    from_json:,
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
pub opaque type Serializer(a) {
  Serializer(adapter: TypeAdapter(a))
}

/// Constructs a `Serializer` from a `TypeAdapter`.
/// Used internally by the Skir client library and by generated code.
pub fn make_serializer(adapter: TypeAdapter(a)) -> Serializer(a) {
  Serializer(adapter:)
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

/// Returns a stub serializer. The stub serializer returns empty/default values
/// and is used in this example project where real serialization is not
/// implemented.
pub fn stub_serializer() -> Serializer(a) {
  make_serializer(TypeAdapter(
    to_dense_json: fn(_) { "[]" },
    to_readable_json: fn(_) { "{}" },
    from_json: fn(_, _) { Error("stub serializer") },
    encode: fn(_) { <<>> },
    decode: fn(_, _) { Error("stub serializer") },
    type_descriptor: type_descriptor.Primitive(type_descriptor.Bool),
  ))
}

/// Serializes a value to dense (field-index-based) JSON.
/// Dense JSON is safe for persistent storage: renaming a field does not break
/// deserialization.
pub fn to_dense_json(serializer: Serializer(a), value: a) -> String {
  serializer.adapter.to_dense_json(value)
}

/// Serializes a value to readable (field-name-based, indented) JSON.
/// Use this for debugging; prefer `to_dense_json` for storage.
pub fn to_readable_json(serializer: Serializer(a), value: a) -> String {
  serializer.adapter.to_readable_json(value)
}

/// Deserializes a value from a JSON string. Accepts both dense and readable
/// JSON. Unrecognized fields are dropped.
pub fn from_json(serializer: Serializer(a), json: String) -> Result(a, String) {
  serializer.adapter.from_json(json, False)
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
  serializer.adapter.from_json(json, keep_unrecognized_values)
}

/// Serializes a value to a compact binary format.
/// The binary format uses the `"skir"` magic prefix followed by the encoded
/// payload produced by the adapter.
pub fn to_bytes(serializer: Serializer(a), value: a) -> BitArray {
  let payload = serializer.adapter.encode(value)
  bit_array.concat([<<"skir":utf8>>, payload])
}

/// Deserializes a value from binary format. Unrecognized fields are dropped.
pub fn from_bytes(
  serializer: Serializer(a),
  bytes: BitArray,
) -> Result(a, String) {
  from_bytes_with_options(serializer, bytes, False)
}

/// Deserializes a value from binary format.
/// When `keep_unrecognized_values` is `True`, field data that this client
/// does not recognise is preserved in `unrecognized_fields_`.
pub fn from_bytes_with_options(
  serializer: Serializer(a),
  bytes: BitArray,
  keep_unrecognized_values keep_unrecognized_values: Bool,
) -> Result(a, String) {
  case bytes {
    <<115, 107, 105, 114, rest:bits>> ->
      serializer.adapter.decode(rest, keep_unrecognized_values)
    _ ->
      case bit_array.to_string(bytes) {
        Ok(s) -> serializer.adapter.from_json(s, keep_unrecognized_values)
        Error(_) -> Error("invalid bytes: not skir binary and not valid UTF-8")
      }
  }
}

/// Returns the TypeDescriptor for the type this serializer handles.
pub fn type_descriptor(serializer: Serializer(a)) -> TypeDescriptor {
  serializer.adapter.type_descriptor
}

// =============================================================================
// Primitive Serializers
// =============================================================================

fn bool_from_json(json_str: String, _keep: Bool) -> Result(Bool, String) {
  case json_str {
    "true" -> Ok(True)
    "false" | "null" -> Ok(False)
    _ ->
      case int.parse(json_str) {
        Ok(n) -> Ok(n != 0)
        Error(_) ->
          case float.parse(json_str) {
            Ok(f) -> Ok(f != 0.0)
            // JSON-encoded string: "0" (3 chars: quote zero quote) is false;
            // any other value is true.
            Error(_) -> Ok(json_str != "\"0\"")
          }
      }
  }
}

fn bool_adapter() -> TypeAdapter(Bool) {
  TypeAdapter(
    to_dense_json: fn(v) {
      case v {
        True -> "1"
        False -> "0"
      }
    },
    to_readable_json: fn(v) {
      case v {
        True -> "true"
        False -> "false"
      }
    },
    from_json: bool_from_json,
    encode: fn(v) {
      case v {
        True -> <<1>>
        False -> <<0>>
      }
    },
    decode: fn(bits, _) {
      case bits {
        <<b, _rest:bits>> -> Ok(b != 0)
        _ -> Error("expected at least 1 byte for bool")
      }
    },
    type_descriptor: type_descriptor.Primitive(type_descriptor.Bool),
  )
}

/// Returns the serializer for Bool values.
pub fn bool_serializer() -> Serializer(Bool) {
  make_serializer(bool_adapter())
}

// -----------------------------------------------------------------------------
// Binary encoding helpers shared by all integer adapters
// -----------------------------------------------------------------------------

// Encodes an i32 using the skir variable-length wire format.
// 0..=231:        single byte (the value itself)
// 232..=65535:    wire 232, then value as u16 LE
// >= 65536:       wire 233, then value as u32 LE
// -256..=-1:      wire 235, then (value + 256) as u8
// -65536..=-257:  wire 236, then (value + 65536) as u16 LE
// < -65536:       wire 237, then value as i32 LE (4 bytes)
fn encode_i32(v: Int) -> BitArray {
  case v {
    _ if v >= 0 && v <= 231 -> <<v>>
    _ if v >= 232 && v <= 65_535 -> <<232, v:size(16)-little>>
    _ if v >= 65_536 -> <<233, v:size(32)-little>>
    _ if v >= -256 && v < 0 -> {
      let b = v + 256
      <<235, b>>
    }
    _ if v >= -65_536 && v < -256 -> {
      let u = v + 65_536
      <<236, u:size(16)-little>>
    }
    _ -> {
      let u = int.bitwise_and(v, 0xFFFF_FFFF)
      <<237, u:size(32)-little>>
    }
  }
}

// Decodes a variable-length number from a BitArray.
// Returns Ok(#(value, rest)) or Error(message).
fn decode_number(bits: BitArray) -> Result(#(Int, BitArray), String) {
  case bits {
    <<wire, rest:bits>> ->
      case wire {
        _ if wire <= 231 -> Ok(#(wire, rest))
        232 ->
          case rest {
            <<v:size(16)-little, r:bits>> -> Ok(#(v, r))
            _ -> Error("unexpected end of input")
          }
        233 ->
          case rest {
            <<v:size(32)-little, r:bits>> -> Ok(#(v, r))
            _ -> Error("unexpected end of input")
          }
        234 ->
          case rest {
            <<v:size(64)-little, r:bits>> -> Ok(#(v, r))
            _ -> Error("unexpected end of input")
          }
        235 ->
          case rest {
            <<b, r:bits>> -> Ok(#(b - 256, r))
            _ -> Error("unexpected end of input")
          }
        236 ->
          case rest {
            <<v:size(16)-little, r:bits>> -> Ok(#(v - 65_536, r))
            _ -> Error("unexpected end of input")
          }
        237 ->
          case rest {
            <<v:size(32)-little-signed, r:bits>> -> Ok(#(v, r))
            _ -> Error("unexpected end of input")
          }
        238 | 239 ->
          case rest {
            <<v:size(64)-little-signed, r:bits>> -> Ok(#(v, r))
            _ -> Error("unexpected end of input")
          }
        _ -> Ok(#(0, rest))
      }
    _ -> Error("unexpected end of input")
  }
}

// Parses a JSON string that should represent an integer.
// Handles: integer literal ("42"), float literal ("3.9" → 3), else 0.
fn int32_from_json_str(s: String) -> Int {
  case int.parse(s) {
    Ok(n) -> n
    Error(_) ->
      case float.parse(s) {
        Ok(f) -> float.truncate(f)
        Error(_) -> 0
      }
  }
}

fn int32_from_json(json_str: String, _keep: Bool) -> Result(Int, String) {
  case json_str {
    "null" -> Ok(0)
    _ ->
      case string.starts_with(json_str, "\"") {
        True -> {
          // JSON string: strip quotes then parse as float→int
          let inner =
            json_str
            |> string.drop_start(1)
            |> string.drop_end(1)
          Ok(int32_from_json_str(inner))
        }
        False -> Ok(int32_from_json_str(json_str))
      }
  }
}

fn int32_adapter() -> TypeAdapter(Int) {
  TypeAdapter(
    to_dense_json: fn(v) { int.to_string(v) },
    to_readable_json: fn(v) { int.to_string(v) },
    from_json: int32_from_json,
    encode: fn(v) { encode_i32(v) },
    decode: fn(bits, _) {
      case decode_number(bits) {
        Ok(#(n, _)) -> Ok(n)
        Error(e) -> Error(e)
      }
    },
    type_descriptor: type_descriptor.Primitive(type_descriptor.Int32),
  )
}

/// Returns the serializer for Int (int32) values.
pub fn int32_serializer() -> Serializer(Int) {
  make_serializer(int32_adapter())
}

// -----------------------------------------------------------------------------
// Int64 adapter
// Max safe integer for JSON: 9_007_199_254_740_991 (2^53 - 1)
// Values within [-MAX, MAX] → JSON number; outside → quoted string.
// -----------------------------------------------------------------------------

const max_safe_int64_json: Int = 9_007_199_254_740_991

fn int64_to_json(v: Int) -> String {
  case v >= -max_safe_int64_json && v <= max_safe_int64_json {
    True -> int.to_string(v)
    False -> "\"" <> int.to_string(v) <> "\""
  }
}

fn int64_from_json(json_str: String, _keep: Bool) -> Result(Int, String) {
  case json_str {
    "null" -> Ok(0)
    _ ->
      case string.starts_with(json_str, "\"") {
        True -> {
          let inner =
            json_str
            |> string.drop_start(1)
            |> string.drop_end(1)
          case int.parse(inner) {
            Ok(n) -> Ok(n)
            Error(_) ->
              case float.parse(inner) {
                Ok(f) -> Ok(float.round(f))
                Error(_) -> Ok(0)
              }
          }
        }
        False ->
          case int.parse(json_str) {
            Ok(n) -> Ok(n)
            Error(_) ->
              case float.parse(json_str) {
                Ok(f) -> Ok(float.round(f))
                Error(_) -> Ok(0)
              }
          }
      }
  }
}

// Encodes an i64.  Values in i32 range reuse i32 encoding; others use wire 238.
fn encode_i64(v: Int) -> BitArray {
  case v >= -2_147_483_648 && v <= 2_147_483_647 {
    True -> encode_i32(v)
    False -> {
      let u = int.bitwise_and(v, 0xFFFF_FFFF_FFFF_FFFF)
      <<238, u:size(64)-little>>
    }
  }
}

fn int64_adapter() -> TypeAdapter(Int) {
  TypeAdapter(
    to_dense_json: fn(v) { int64_to_json(v) },
    to_readable_json: fn(v) { int64_to_json(v) },
    from_json: int64_from_json,
    encode: fn(v) { encode_i64(v) },
    decode: fn(bits, _) {
      case decode_number(bits) {
        Ok(#(n, _)) -> Ok(n)
        Error(e) -> Error(e)
      }
    },
    type_descriptor: type_descriptor.Primitive(type_descriptor.Int64),
  )
}

/// Returns the serializer for Int (int64) values.
pub fn int64_serializer() -> Serializer(Int) {
  make_serializer(int64_adapter())
}

// -----------------------------------------------------------------------------
// Hash64 adapter  (unsigned 64-bit integer, stored as Gleam Int)
// Wire format: same variable-length uint scheme used by encode_uint32, extended
// to u64: 0-231 single byte; 232-65535 wire232+u16LE; 65536-4294967295
// wire233+u32LE; >= 2^32 wire234+u64LE.
// -----------------------------------------------------------------------------

const max_safe_hash64_json: Int = 9_007_199_254_740_991

fn hash64_to_json(v: Int) -> String {
  case v <= max_safe_hash64_json {
    True -> int.to_string(v)
    False -> "\"" <> int.to_string(v) <> "\""
  }
}

fn hash64_from_json(json_str: String, _keep: Bool) -> Result(Int, String) {
  case json_str {
    "null" -> Ok(0)
    _ ->
      case string.starts_with(json_str, "\"") {
        True -> {
          let inner =
            json_str
            |> string.drop_start(1)
            |> string.drop_end(1)
          case int.parse(inner) {
            Ok(n) -> Ok(n)
            Error(_) ->
              case float.parse(inner) {
                Ok(f) -> Ok(float.round(f))
                Error(_) -> Ok(0)
              }
          }
        }
        False ->
          case float.parse(json_str) {
            Ok(f) if f <. 0.0 -> Ok(0)
            Ok(_) ->
              case int.parse(json_str) {
                Ok(n) -> Ok(n)
                Error(_) ->
                  case float.parse(json_str) {
                    Ok(f) -> Ok(float.round(f))
                    Error(_) -> Ok(0)
                  }
              }
            Error(_) ->
              case int.parse(json_str) {
                Ok(n) -> Ok(n)
                Error(_) -> Ok(0)
              }
          }
      }
  }
}

fn encode_uint64(v: Int) -> BitArray {
  case v {
    _ if v <= 231 -> <<v>>
    _ if v <= 65_535 -> <<232, v:size(16)-little>>
    _ if v <= 4_294_967_295 -> <<233, v:size(32)-little>>
    _ -> <<234, v:size(64)-little>>
  }
}

fn hash64_adapter() -> TypeAdapter(Int) {
  TypeAdapter(
    to_dense_json: fn(v) { hash64_to_json(v) },
    to_readable_json: fn(v) { hash64_to_json(v) },
    from_json: hash64_from_json,
    encode: fn(v) { encode_uint64(v) },
    decode: fn(bits, _) {
      case decode_number(bits) {
        Ok(#(n, _)) -> Ok(n)
        Error(e) -> Error(e)
      }
    },
    type_descriptor: type_descriptor.Primitive(type_descriptor.Hash64),
  )
}

/// Returns the serializer for Int (hash64) values.
pub fn hash64_serializer() -> Serializer(Int) {
  make_serializer(hash64_adapter())
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
pub fn list_serializer(item_serializer: Serializer(a)) -> Serializer(List(a)) {
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

/// Serializes a TypeDescriptor to a JSON string.
/// The format is compatible with the Go and Rust skir client implementations.
pub fn type_descriptor_to_json(td: TypeDescriptor) -> String {
  type_descriptor.type_descriptor_to_json(td)
}

/// Parses a TypeDescriptor from a JSON string.
/// Accepts JSON produced by this module or by the Go/Rust skir client implementations.
pub fn type_descriptor_from_json(json: String) -> Result(TypeDescriptor, String) {
  type_descriptor.type_descriptor_from_json(json)
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
