import gleeunit/should
import skir_client

// =============================================================================
// to_dense_json
// =============================================================================

pub fn to_dense_json_empty_string_test() {
  skir_client.to_dense_json(skir_client.string_serializer(), "")
  |> should.equal("\"\"")
}

pub fn to_dense_json_simple_string_test() {
  skir_client.to_dense_json(skir_client.string_serializer(), "hello")
  |> should.equal("\"hello\"")
}

pub fn to_dense_json_escapes_double_quote_test() {
  skir_client.to_dense_json(skir_client.string_serializer(), "say \"hi\"")
  |> should.equal("\"say \\\"hi\\\"\"")
}

pub fn to_dense_json_escapes_backslash_test() {
  skir_client.to_dense_json(skir_client.string_serializer(), "a\\b")
  |> should.equal("\"a\\\\b\"")
}

pub fn to_dense_json_escapes_newline_test() {
  skir_client.to_dense_json(skir_client.string_serializer(), "a\nb")
  |> should.equal("\"a\\nb\"")
}

// =============================================================================
// to_readable_json
// =============================================================================

pub fn to_readable_json_simple_string_test() {
  // Strings are quoted identically in dense and readable JSON.
  skir_client.to_readable_json(skir_client.string_serializer(), "hello")
  |> should.equal("\"hello\"")
}

pub fn to_readable_json_empty_string_test() {
  skir_client.to_readable_json(skir_client.string_serializer(), "")
  |> should.equal("\"\"")
}

// =============================================================================
// from_json
// =============================================================================

pub fn from_json_string_test() {
  skir_client.from_json(skir_client.string_serializer(), "\"hello\"")
  |> should.be_ok
  |> should.equal("hello")
}

pub fn from_json_empty_string_test() {
  skir_client.from_json(skir_client.string_serializer(), "\"\"")
  |> should.be_ok
  |> should.equal("")
}

pub fn from_json_number_yields_empty_string_test() {
  // Any number is treated as the default (empty string).
  skir_client.from_json(skir_client.string_serializer(), "0")
  |> should.be_ok
  |> should.equal("")
}

pub fn from_json_null_yields_empty_string_test() {
  skir_client.from_json(skir_client.string_serializer(), "null")
  |> should.be_ok
  |> should.equal("")
}

pub fn from_json_round_trip_test() {
  let s = skir_client.string_serializer()
  let value = "round trip"
  skir_client.to_dense_json(s, value)
  |> skir_client.from_json(s, _)
  |> should.be_ok
  |> should.equal(value)
}

// =============================================================================
// binary encoding
// =============================================================================

pub fn binary_encoding_empty_is_wire_242_test() {
  // empty string → skir prefix (4 bytes) + wire 242
  skir_client.to_bytes(skir_client.string_serializer(), "")
  |> should.equal(<<115, 107, 105, 114, 242>>)
}

pub fn binary_encoding_hello_test() {
  // "hello" = [104,101,108,108,111], len=5 (single-byte length)
  // → skir + 243 + 5 + utf8("hello")
  skir_client.to_bytes(skir_client.string_serializer(), "hello")
  |> should.equal(<<115, 107, 105, 114, 243, 5, 104, 101, 108, 108, 111>>)
}

// =============================================================================
// binary round-trip
// =============================================================================

pub fn binary_round_trip_empty_test() {
  let s = skir_client.string_serializer()
  skir_client.to_bytes(s, "")
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal("")
}

pub fn binary_round_trip_simple_test() {
  let s = skir_client.string_serializer()
  skir_client.to_bytes(s, "hello")
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal("hello")
}

pub fn binary_round_trip_unicode_test() {
  let s = skir_client.string_serializer()
  let value = "héllo wörld"
  skir_client.to_bytes(s, value)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal(value)
}

// =============================================================================
// type_descriptor
// =============================================================================

pub fn type_descriptor_is_string_test() {
  let td = skir_client.type_descriptor(skir_client.string_serializer())
  let json = skir_client.type_descriptor_to_json(td)
  let expected =
    "{\n  \"type\": {\n    \"kind\": \"primitive\",\n    \"value\": \"string\"\n  },\n  \"records\": []\n}"
  should.equal(json, expected)
}
