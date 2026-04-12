import gleeunit/should
import skir_client

// =============================================================================
// to_dense_json
// =============================================================================

pub fn to_dense_json_true_is_1_test() {
  skir_client.to_dense_json(skir_client.bool_serializer(), True)
  |> should.equal("1")
}

pub fn to_dense_json_false_is_0_test() {
  skir_client.to_dense_json(skir_client.bool_serializer(), False)
  |> should.equal("0")
}

// =============================================================================
// to_readable_json
// =============================================================================

pub fn to_readable_json_true_is_true_test() {
  skir_client.to_readable_json(skir_client.bool_serializer(), True)
  |> should.equal("true")
}

pub fn to_readable_json_false_is_false_test() {
  skir_client.to_readable_json(skir_client.bool_serializer(), False)
  |> should.equal("false")
}

// =============================================================================
// from_json
// =============================================================================

pub fn from_json_bool_literal_test() {
  let s = skir_client.bool_serializer()
  skir_client.from_json(s, "true")
  |> should.be_ok
  |> should.be_true
  skir_client.from_json(s, "false")
  |> should.be_ok
  |> should.be_false
}

pub fn from_json_number_1_and_0_test() {
  let s = skir_client.bool_serializer()
  skir_client.from_json(s, "1")
  |> should.be_ok
  |> should.be_true
  skir_client.from_json(s, "0")
  |> should.be_ok
  |> should.be_false
}

pub fn from_json_number_nonzero_test() {
  skir_client.from_json(skir_client.bool_serializer(), "42")
  |> should.be_ok
  |> should.be_true
}

pub fn from_json_float_zero_test() {
  skir_client.from_json(skir_client.bool_serializer(), "0.0")
  |> should.be_ok
  |> should.be_false
}

pub fn from_json_string_zero_is_false_test() {
  // The JSON string "0" (three chars: quote, zero, quote) is the only falsy
  // string value.
  skir_client.from_json(skir_client.bool_serializer(), "\"0\"")
  |> should.be_ok
  |> should.be_false
}

pub fn from_json_string_nonzero_is_true_test() {
  let s = skir_client.bool_serializer()
  skir_client.from_json(s, "\"1\"")
  |> should.be_ok
  |> should.be_true
  skir_client.from_json(s, "\"true\"")
  |> should.be_ok
  |> should.be_true
}

pub fn from_json_null_is_false_test() {
  skir_client.from_json(skir_client.bool_serializer(), "null")
  |> should.be_ok
  |> should.be_false
}

// =============================================================================
// binary round-trip
// =============================================================================

pub fn binary_round_trip_true_test() {
  let s = skir_client.bool_serializer()
  let bytes = skir_client.to_bytes(s, True)
  skir_client.from_bytes(s, bytes)
  |> should.be_ok
  |> should.be_true
}

pub fn binary_round_trip_false_test() {
  let s = skir_client.bool_serializer()
  let bytes = skir_client.to_bytes(s, False)
  skir_client.from_bytes(s, bytes)
  |> should.be_ok
  |> should.be_false
}

pub fn binary_encoding_true_is_skir_then_1_test() {
  skir_client.to_bytes(skir_client.bool_serializer(), True)
  |> should.equal(<<115, 107, 105, 114, 1>>)
}

pub fn binary_encoding_false_is_skir_then_0_test() {
  skir_client.to_bytes(skir_client.bool_serializer(), False)
  |> should.equal(<<115, 107, 105, 114, 0>>)
}

// =============================================================================
// type_descriptor
// =============================================================================

pub fn type_descriptor_is_bool_test() {
  let td = skir_client.type_descriptor(skir_client.bool_serializer())
  let json = skir_client.type_descriptor_to_json(td)
  let expected =
    "{\n  \"type\": {\n    \"kind\": \"primitive\",\n    \"value\": \"bool\"\n  },\n  \"records\": []\n}"
  should.equal(json, expected)
}
