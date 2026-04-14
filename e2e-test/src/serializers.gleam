import gleam/bit_array
import gleam/bytes_tree
import gleam/dynamic/decode.{type Decoder}
import gleam/float
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/string_tree
import gleam/time/calendar
import gleam/time/timestamp.{type Timestamp}
import serializer.{
  type Serializer, type TypeAdapter, TypeAdapter, get_adapter, make_serializer,
}
import type_descriptor

// =============================================================================
// Primitive Serializers
// =============================================================================

fn bool_adapter() -> TypeAdapter(Bool) {
  TypeAdapter(
    append_json: fn(v, tree, eol_indent) {
      let s = case eol_indent {
        "" ->
          case v {
            True -> "1"
            False -> "0"
          }
        _ ->
          case v {
            True -> "true"
            False -> "false"
          }
      }
      string_tree.append(tree, s)
    },
    json_decoder: decode.one_of(decode.bool, [
      decode.int |> decode.map(fn(n) { n != 0 }),
      decode.float |> decode.map(fn(f) { f != 0.0 }),
      decode.string |> decode.map(fn(s) { s != "0" }),
      decode.optional(decode.bool)
        |> decode.map(fn(opt) { option.unwrap(opt, False) }),
    ]),
    encode: fn(v, acc) {
      bytes_tree.append(acc, case v {
        True -> <<1>>
        False -> <<0>>
      })
    },
    decode: fn(bits, _) {
      case bits {
        <<b, rest:bits>> -> Ok(#(b != 0, rest))
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

fn int32_adapter() -> TypeAdapter(Int) {
  TypeAdapter(
    append_json: fn(v, tree, _) { string_tree.append(tree, int.to_string(v)) },
    json_decoder: decode.one_of(decode.int, [
      decode.float |> decode.map(float.truncate),
      decode.string |> decode.map(int32_from_json_str),
      decode.optional(decode.int)
        |> decode.map(fn(opt) { option.unwrap(opt, 0) }),
    ]),
    encode: fn(v, acc) { bytes_tree.append(acc, encode_i32(v)) },
    decode: fn(bits, _) { decode_number(bits) },
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

fn int64_adapter() -> TypeAdapter(Int) {
  let parse_string = fn(s) {
    case int.parse(s) {
      Ok(n) -> n
      Error(_) ->
        case float.parse(s) {
          Ok(f) -> float.round(f)
          Error(_) -> 0
        }
    }
  }
  TypeAdapter(
    append_json: fn(v, tree, _) { string_tree.append(tree, int64_to_json(v)) },
    json_decoder: decode.one_of(decode.int, [
      decode.float |> decode.map(float.round),
      decode.string |> decode.map(parse_string),
      decode.optional(decode.int)
        |> decode.map(fn(opt) { option.unwrap(opt, 0) }),
    ]),
    encode: fn(v, acc) { bytes_tree.append(acc, encode_i64(v)) },
    decode: fn(bits, _) { decode_number(bits) },
    type_descriptor: type_descriptor.Primitive(type_descriptor.Int64),
  )
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

fn hash64_adapter() -> TypeAdapter(Int) {
  let parse_string = fn(s) {
    case int.parse(s) {
      Ok(n) -> n
      Error(_) ->
        case float.parse(s) {
          Ok(f) -> float.round(f)
          Error(_) -> 0
        }
    }
  }
  TypeAdapter(
    append_json: fn(v, tree, _) { string_tree.append(tree, hash64_to_json(v)) },
    json_decoder: decode.one_of(decode.int, [
      decode.float
        |> decode.map(fn(f) {
          case f <. 0.0 {
            True -> 0
            False -> float.round(f)
          }
        }),
      decode.string |> decode.map(parse_string),
      decode.optional(decode.int)
        |> decode.map(fn(opt) { option.unwrap(opt, 0) }),
    ]),
    encode: fn(v, acc) { bytes_tree.append(acc, encode_uint64(v)) },
    decode: fn(bits, _) { decode_number(bits) },
    type_descriptor: type_descriptor.Primitive(type_descriptor.Hash64),
  )
}

fn encode_uint64(v: Int) -> BitArray {
  case v {
    _ if v <= 231 -> <<v>>
    _ if v <= 65_535 -> <<232, v:size(16)-little>>
    _ if v <= 4_294_967_295 -> <<233, v:size(32)-little>>
    _ -> <<234, v:size(64)-little>>
  }
}

/// Returns the serializer for Int (hash64) values.
pub fn hash64_serializer() -> Serializer(Int) {
  make_serializer(hash64_adapter())
}

// ---------------------------------------------------------------------------
// Float helpers
// ---------------------------------------------------------------------------

// Converts a float to a JSON string, stripping the trailing ".0" that
// Erlang's float formatter adds to whole-number floats (e.g. 1.0 → "1").
fn float_to_json_str(f: Float) -> String {
  let s = float.to_string(f)
  case string.ends_with(s, ".0") {
    True -> string.drop_end(s, 2)
    False -> s
  }
}

fn float_json_decoder() -> Decoder(Float) {
  decode.one_of(decode.float, [
    decode.int |> decode.map(int.to_float),
    decode.string
      |> decode.map(fn(s) {
        case s {
          "NaN" | "Infinity" | "-Infinity" -> 0.0
          _ ->
            case float.parse(s) {
              Ok(f) -> f
              Error(_) ->
                case int.parse(s) {
                  Ok(n) -> int.to_float(n)
                  Error(_) -> 0.0
                }
            }
        }
      }),
    decode.optional(decode.float)
      |> decode.map(fn(opt) { option.unwrap(opt, 0.0) }),
  ])
}

fn float32_adapter() -> TypeAdapter(Float) {
  TypeAdapter(
    append_json: fn(v, tree, _) {
      string_tree.append(tree, float_to_json_str(v))
    },
    json_decoder: float_json_decoder(),
    encode: fn(v, acc) {
      bytes_tree.append(acc, case v {
        0.0 -> <<0>>
        _ -> <<240, v:float-size(32)-little>>
      })
    },
    decode: fn(bits, _) {
      case bits {
        <<240, rest:bits>> ->
          case rest {
            <<v:float-size(32)-little, remaining:bits>> -> Ok(#(v, remaining))
            _ -> Error("truncated float32 data")
          }
        _ ->
          case decode_number(bits) {
            Ok(#(n, rest)) -> Ok(#(int.to_float(n), rest))
            Error(e) -> Error(e)
          }
      }
    },
    type_descriptor: type_descriptor.Primitive(type_descriptor.Float32),
  )
}

/// Returns the serializer for Float (float32) values.
pub fn float32_serializer() -> Serializer(Float) {
  make_serializer(float32_adapter())
}

fn float64_adapter() -> TypeAdapter(Float) {
  TypeAdapter(
    append_json: fn(v, tree, _) {
      string_tree.append(tree, float_to_json_str(v))
    },
    json_decoder: float_json_decoder(),
    encode: fn(v, acc) {
      bytes_tree.append(acc, case v {
        0.0 -> <<0>>
        _ -> <<241, v:float-size(64)-little>>
      })
    },
    decode: fn(bits, _) {
      case bits {
        <<241, rest:bits>> ->
          case rest {
            <<v:float-size(64)-little, remaining:bits>> -> Ok(#(v, remaining))
            _ -> Error("truncated float64 data")
          }
        _ ->
          case decode_number(bits) {
            Ok(#(n, rest)) -> Ok(#(int.to_float(n), rest))
            Error(e) -> Error(e)
          }
      }
    },
    type_descriptor: type_descriptor.Primitive(type_descriptor.Float64),
  )
}

/// Returns the serializer for Float (float64) values.
pub fn float64_serializer() -> Serializer(Float) {
  make_serializer(float64_adapter())
}

// ---------------------------------------------------------------------------
// Base64 and hex helpers (used by bytes_adapter)
// ---------------------------------------------------------------------------

const base64_alphabet: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

fn base64_char(i: Int) -> String {
  string.slice(base64_alphabet, i, 1)
}

fn encode_base64(bs: BitArray) -> String {
  encode_base64_acc(bs, string_tree.new()) |> string_tree.to_string
}

fn encode_base64_acc(bs: BitArray, acc) -> _ {
  case bs {
    <<>> -> acc
    <<a:size(6), b:size(6), c:size(6), d:size(6), rest:bits>> ->
      encode_base64_acc(
        rest,
        acc
          |> string_tree.append(base64_char(a))
          |> string_tree.append(base64_char(b))
          |> string_tree.append(base64_char(c))
          |> string_tree.append(base64_char(d)),
      )
    <<a:size(6), b:size(6), c:size(4)>> ->
      acc
      |> string_tree.append(base64_char(a))
      |> string_tree.append(base64_char(b))
      |> string_tree.append(base64_char(int.bitwise_shift_left(c, 2)))
      |> string_tree.append("=")
    <<a:size(6), b:size(2)>> ->
      acc
      |> string_tree.append(base64_char(a))
      |> string_tree.append(base64_char(int.bitwise_shift_left(b, 4)))
      |> string_tree.append("==")
    _ -> acc
  }
}

fn base64_char_to_int(c: Int) -> Result(Int, String) {
  case c {
    _ if c >= 65 && c <= 90 -> Ok(c - 65)
    _ if c >= 97 && c <= 122 -> Ok(c - 71)
    _ if c >= 48 && c <= 57 -> Ok(c + 4)
    43 -> Ok(62)
    47 -> Ok(63)
    _ -> Error("invalid base64 character")
  }
}

fn strip_base64_padding(s: String) -> String {
  case string.ends_with(s, "==") {
    True -> string.drop_end(s, 2)
    False ->
      case string.ends_with(s, "=") {
        True -> string.drop_end(s, 1)
        False -> s
      }
  }
}

fn decode_base64(s: String) -> Result(BitArray, String) {
  do_decode_base64(
    bit_array.from_string(strip_base64_padding(s)),
    bytes_tree.new(),
  )
}

fn do_decode_base64(chars: BitArray, acc) -> Result(BitArray, String) {
  case chars {
    <<>> -> Ok(bytes_tree.to_bit_array(acc))
    <<a, b, c, d, rest:bits>> ->
      case base64_char_to_int(a) {
        Error(e) -> Error(e)
        Ok(va) ->
          case base64_char_to_int(b) {
            Error(e) -> Error(e)
            Ok(vb) ->
              case base64_char_to_int(c) {
                Error(e) -> Error(e)
                Ok(vc) ->
                  case base64_char_to_int(d) {
                    Error(e) -> Error(e)
                    Ok(vd) -> {
                      let n =
                        int.bitwise_or(
                          int.bitwise_or(
                            int.bitwise_or(
                              int.bitwise_shift_left(va, 18),
                              int.bitwise_shift_left(vb, 12),
                            ),
                            int.bitwise_shift_left(vc, 6),
                          ),
                          vd,
                        )
                      let b1 =
                        int.bitwise_shift_right(n, 16)
                        |> int.bitwise_and(0xFF)
                      let b2 =
                        int.bitwise_shift_right(n, 8)
                        |> int.bitwise_and(0xFF)
                      let b3 = int.bitwise_and(n, 0xFF)
                      do_decode_base64(
                        rest,
                        bytes_tree.append(acc, <<b1, b2, b3>>),
                      )
                    }
                  }
              }
          }
      }
    <<a, b, c>> ->
      case base64_char_to_int(a) {
        Error(e) -> Error(e)
        Ok(va) ->
          case base64_char_to_int(b) {
            Error(e) -> Error(e)
            Ok(vb) ->
              case base64_char_to_int(c) {
                Error(e) -> Error(e)
                Ok(vc) -> {
                  let n =
                    int.bitwise_or(
                      int.bitwise_or(
                        int.bitwise_shift_left(va, 18),
                        int.bitwise_shift_left(vb, 12),
                      ),
                      int.bitwise_shift_left(vc, 6),
                    )
                  let b1 =
                    int.bitwise_shift_right(n, 16) |> int.bitwise_and(0xFF)
                  let b2 =
                    int.bitwise_shift_right(n, 8) |> int.bitwise_and(0xFF)
                  Ok(
                    bytes_tree.to_bit_array(bytes_tree.append(acc, <<b1, b2>>)),
                  )
                }
              }
          }
      }
    <<a, b>> ->
      case base64_char_to_int(a) {
        Error(e) -> Error(e)
        Ok(va) ->
          case base64_char_to_int(b) {
            Error(e) -> Error(e)
            Ok(vb) -> {
              let n =
                int.bitwise_or(
                  int.bitwise_shift_left(va, 18),
                  int.bitwise_shift_left(vb, 12),
                )
              let b1 = int.bitwise_shift_right(n, 16) |> int.bitwise_and(0xFF)
              Ok(bytes_tree.to_bit_array(bytes_tree.append(acc, <<b1>>)))
            }
          }
      }
    _ -> Error("invalid base64 data")
  }
}

fn encode_hex(bs: BitArray) -> String {
  encode_hex_acc(bs, string_tree.new()) |> string_tree.to_string
}

fn encode_hex_acc(bs: BitArray, acc) -> _ {
  case bs {
    <<>> -> acc
    <<b, rest:bits>> ->
      encode_hex_acc(
        rest,
        acc
          |> string_tree.append(hex_digit(b / 16))
          |> string_tree.append(hex_digit(b % 16)),
      )
    _ -> acc
  }
}

fn hex_digit(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    9 -> "9"
    10 -> "a"
    11 -> "b"
    12 -> "c"
    13 -> "d"
    14 -> "e"
    _ -> "f"
  }
}

fn decode_hex(s: String) -> Result(BitArray, String) {
  let n = string.length(s)
  case n % 2 {
    0 -> do_decode_hex(bit_array.from_string(s), bytes_tree.new())
    _ -> Error("odd hex string length: " <> int.to_string(n))
  }
}

fn do_decode_hex(bs: BitArray, acc) -> Result(BitArray, String) {
  case bs {
    <<>> -> Ok(bytes_tree.to_bit_array(acc))
    <<hi, lo, rest:bits>> ->
      case hex_char_to_int(hi) {
        Error(e) -> Error(e)
        Ok(h) ->
          case hex_char_to_int(lo) {
            Error(e) -> Error(e)
            Ok(l) -> {
              let byte = h * 16 + l
              do_decode_hex(rest, bytes_tree.append(acc, <<byte>>))
            }
          }
      }
    _ -> Error("unexpected end of hex input")
  }
}

fn hex_char_to_int(c: Int) -> Result(Int, String) {
  case c {
    _ if c >= 48 && c <= 57 -> Ok(c - 48)
    _ if c >= 65 && c <= 70 -> Ok(c - 55)
    _ if c >= 97 && c <= 102 -> Ok(c - 87)
    _ -> Error("invalid hex character")
  }
}

// ---------------------------------------------------------------------------
// String adapter
// ---------------------------------------------------------------------------

fn string_adapter() -> TypeAdapter(String) {
  TypeAdapter(
    append_json: fn(v, tree, _) {
      string_tree.append(tree, json.to_string(json.string(v)))
    },
    json_decoder: decode.one_of(decode.string, [
      decode.int |> decode.map(fn(_) { "" }),
      decode.float |> decode.map(fn(_) { "" }),
      decode.optional(decode.string)
        |> decode.map(fn(opt) { option.unwrap(opt, "") }),
    ]),
    encode: fn(v, acc) {
      case v {
        "" -> bytes_tree.append(acc, <<242>>)
        _ -> {
          let bs = bit_array.from_string(v)
          let len = bit_array.byte_size(bs)
          acc
          |> bytes_tree.append(<<243>>)
          |> bytes_tree.append(encode_uint64(len))
          |> bytes_tree.append(bs)
        }
      }
    },
    decode: fn(bits, _) {
      case bits {
        <<wire, rest:bits>> ->
          case wire {
            0 | 242 -> Ok(#("", rest))
            _ ->
              case decode_number(rest) {
                Error(e) -> Error(e)
                Ok(#(n, after_len)) ->
                  case n {
                    0 -> Ok(#("", after_len))
                    _ ->
                      case after_len {
                        <<data:bytes-size(n), remaining:bits>> ->
                          case bit_array.to_string(data) {
                            Ok(s) -> Ok(#(s, remaining))
                            Error(_) -> Error("invalid UTF-8 in string data")
                          }
                        _ -> Error("not enough data for string field")
                      }
                  }
              }
          }
        _ -> Error("unexpected end of input")
      }
    },
    type_descriptor: type_descriptor.Primitive(type_descriptor.StringType),
  )
}

/// Returns the serializer for String values.
pub fn string_serializer() -> Serializer(String) {
  make_serializer(string_adapter())
}

// ---------------------------------------------------------------------------
// Bytes adapter
// ---------------------------------------------------------------------------

fn bytes_adapter() -> TypeAdapter(BitArray) {
  TypeAdapter(
    append_json: fn(v, tree, eol_indent) {
      let encoded = case eol_indent {
        "" -> "\"" <> encode_base64(v) <> "\""
        _ -> "\"hex:" <> encode_hex(v) <> "\""
      }
      string_tree.append(tree, encoded)
    },
    json_decoder: decode.one_of(
      decode.string
        |> decode.then(fn(s) {
          let r = case string.starts_with(s, "hex:") {
            True -> decode_hex(string.drop_start(s, 4))
            False -> decode_base64(s)
          }
          case r {
            Ok(bs) -> decode.success(bs)
            Error(e) -> decode.failure(<<>>, e)
          }
        }),
      [
        decode.int |> decode.map(fn(_) { <<>> }),
        decode.float |> decode.map(fn(_) { <<>> }),
        decode.optional(decode.string) |> decode.map(fn(_) { <<>> }),
      ],
    ),
    encode: fn(v, acc) {
      case v {
        <<>> -> bytes_tree.append(acc, <<244>>)
        _ -> {
          let len = bit_array.byte_size(v)
          acc
          |> bytes_tree.append(<<245>>)
          |> bytes_tree.append(encode_uint64(len))
          |> bytes_tree.append(v)
        }
      }
    },
    decode: fn(bits, _) {
      case bits {
        <<wire, rest:bits>> ->
          case wire {
            0 | 244 -> Ok(#(<<>>, rest))
            _ ->
              case decode_number(rest) {
                Error(e) -> Error(e)
                Ok(#(n, after_len)) ->
                  case n {
                    0 -> Ok(#(<<>>, after_len))
                    _ ->
                      case after_len {
                        <<data:bytes-size(n), remaining:bits>> ->
                          Ok(#(data, remaining))
                        _ -> Error("not enough data for bytes field")
                      }
                  }
              }
          }
        _ -> Error("unexpected end of input")
      }
    },
    type_descriptor: type_descriptor.Primitive(type_descriptor.Bytes),
  )
}

/// Returns the serializer for BitArray (bytes) values.
pub fn bytes_serializer() -> Serializer(BitArray) {
  make_serializer(bytes_adapter())
}

// ---------------------------------------------------------------------------
// Timestamp helpers
// ---------------------------------------------------------------------------

// Encodes unix milliseconds. Values in i32 range reuse i32 encoding;
// others use wire 239 (decoded identically to wire 238, 64-bit signed LE).
fn encode_timestamp(ms: Int) -> BitArray {
  case ms >= -2_147_483_648 && ms <= 2_147_483_647 {
    True -> encode_i32(ms)
    False -> {
      let u = int.bitwise_and(ms, 0xFFFF_FFFF_FFFF_FFFF)
      <<239, u:size(64)-little>>
    }
  }
}

fn timestamp_adapter() -> TypeAdapter(Timestamp) {
  let from_unix_milli = fn(ms: Int) -> Timestamp {
    timestamp.from_unix_seconds_and_nanoseconds(
      seconds: ms / 1000,
      nanoseconds: ms % 1000 * 1_000_000,
    )
  }
  let to_unix_milli = fn(ts: Timestamp) -> Int {
    let #(s, ns) = timestamp.to_unix_seconds_and_nanoseconds(ts)
    s * 1000 + ns / 1_000_000
  }
  let parse_millis_string = fn(s) {
    case int.parse(s) {
      Ok(n) -> n
      Error(_) ->
        case float.parse(s) {
          Ok(f) -> float.round(f)
          Error(_) -> 0
        }
    }
  }
  TypeAdapter(
    append_json: fn(v, tree, eol_indent) {
      let ms = to_unix_milli(v)
      case eol_indent {
        "" -> string_tree.append(tree, int.to_string(ms))
        _ -> {
          let child_indent = eol_indent <> "  "
          let iso = timestamp.to_rfc3339(v, calendar.utc_offset)
          tree
          |> string_tree.append("{")
          |> string_tree.append(child_indent)
          |> string_tree.append("\"unix_millis\": ")
          |> string_tree.append(int.to_string(ms))
          |> string_tree.append(",")
          |> string_tree.append(child_indent)
          |> string_tree.append("\"formatted\": \"")
          |> string_tree.append(iso)
          |> string_tree.append("\"")
          |> string_tree.append(eol_indent)
          |> string_tree.append("}")
        }
      }
    },
    json_decoder: decode.one_of(decode.int |> decode.map(from_unix_milli), [
      decode.float
        |> decode.map(fn(f) { from_unix_milli(float.round(f)) }),
      {
        use unix_millis <- decode.field("unix_millis", decode.int)
        decode.success(from_unix_milli(unix_millis))
      },
      decode.string
        |> decode.map(fn(s) { from_unix_milli(parse_millis_string(s)) }),
      decode.optional(decode.int)
        |> decode.map(fn(opt) { from_unix_milli(option.unwrap(opt, 0)) }),
    ]),
    encode: fn(v, acc) {
      bytes_tree.append(acc, encode_timestamp(to_unix_milli(v)))
    },
    decode: fn(bits, _) {
      case decode_number(bits) {
        Ok(#(ms, rest)) -> Ok(#(from_unix_milli(ms), rest))
        Error(e) -> Error(e)
      }
    },
    type_descriptor: type_descriptor.Primitive(type_descriptor.Timestamp),
  )
}

/// Returns the serializer for Timestamp values.
pub fn timestamp_serializer() -> Serializer(Timestamp) {
  make_serializer(timestamp_adapter())
}

// =============================================================================
// Composite Serializers
// =============================================================================

fn optional_adapter(item_serializer: Serializer(a)) -> TypeAdapter(Option(a)) {
  let item = get_adapter(item_serializer)
  TypeAdapter(
    append_json: fn(v, tree, eol_indent) {
      case v {
        None -> string_tree.append(tree, "null")
        Some(x) -> item.append_json(x, tree, eol_indent)
      }
    },
    json_decoder: decode.optional(item.json_decoder),
    encode: fn(v, acc) {
      case v {
        None -> bytes_tree.append(acc, <<0>>)
        Some(x) -> item.encode(x, bytes_tree.append(acc, <<1>>))
      }
    },
    decode: fn(bits, strict) {
      case bits {
        <<0, rest:bits>> -> Ok(#(None, rest))
        <<1, rest:bits>> ->
          case item.decode(rest, strict) {
            Ok(#(x, remaining)) -> Ok(#(Some(x), remaining))
            Error(e) -> Error(e)
          }
        _ -> Error("expected 0 or 1 byte for optional tag")
      }
    },
    type_descriptor: type_descriptor.Optional(item.type_descriptor),
  )
}

/// Returns a serializer for Option(a) values.
pub fn optional_serializer(
  item_serializer: Serializer(a),
) -> Serializer(Option(a)) {
  make_serializer(optional_adapter(item_serializer))
}

fn list_adapter(item_serializer: Serializer(a)) -> TypeAdapter(List(a)) {
  let item = get_adapter(item_serializer)
  TypeAdapter(
    append_json: fn(v, tree, eol_indent) {
      case v {
        [] -> string_tree.append(tree, "[]")
        _ -> {
          let #(child_indent, closing) = case eol_indent {
            "" -> #("", "]")
            _ -> #(eol_indent <> "  ", eol_indent <> "]")
          }
          let tree = string_tree.append(tree, "[")
          let #(tree, _) =
            list_fold(v, #(tree, True), fn(pair, item_val) {
              let #(t, is_first) = pair
              let t = case is_first {
                True -> t
                False -> string_tree.append(t, ",")
              }
              let t = string_tree.append(t, child_indent)
              #(item.append_json(item_val, t, child_indent), False)
            })
          string_tree.append(tree, closing)
        }
      }
    },
    json_decoder: decode.one_of(decode.list(item.json_decoder), [
      decode.int |> decode.map(fn(_) { [] }),
    ]),
    encode: fn(v, acc) {
      let count = list_fold(v, 0, fn(n, _) { n + 1 })
      let acc = bytes_tree.append(acc, encode_uint64(count))
      list_fold(v, acc, fn(bytes_acc, item_val) {
        item.encode(item_val, bytes_acc)
      })
    },
    decode: fn(bits, strict) {
      case decode_number(bits) {
        Error(e) -> Error(e)
        Ok(#(count, rest)) -> decode_list_items(item, count, rest, strict, [])
      }
    },
    type_descriptor: type_descriptor.Array(
      item_type: item.type_descriptor,
      key_extractor: "",
    ),
  )
}

/// Returns a serializer for List(a) values.
pub fn list_serializer(item_serializer: Serializer(a)) -> Serializer(List(a)) {
  make_serializer(list_adapter(item_serializer))
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

fn list_reverse(lst: List(a)) -> List(a) {
  list_fold(lst, [], fn(acc, x) { [x, ..acc] })
}

fn decode_list_items(
  item: TypeAdapter(a),
  count: Int,
  bits: BitArray,
  strict: Bool,
  acc: List(a),
) -> Result(#(List(a), BitArray), String) {
  case count {
    0 -> Ok(#(list_reverse(acc), bits))
    _ ->
      case item.decode(bits, strict) {
        Error(e) -> Error(e)
        Ok(#(v, rest)) ->
          decode_list_items(item, count - 1, rest, strict, [v, ..acc])
      }
  }
}
