import gleeunit/should
import skir_client

// =============================================================================
// to_dense_json   (standard base64 with = padding)
// =============================================================================

pub fn to_dense_json_empty_bytes_test() {
  skir_client.to_dense_json(skir_client.bytes_serializer(), <<>>)
  |> should.equal("\"\"")
}

pub fn to_dense_json_single_byte_test() {
  // <<0>> → base64 "AA=="
  skir_client.to_dense_json(skir_client.bytes_serializer(), <<0>>)
  |> should.equal("\"AA==\"")
}

pub fn to_dense_json_two_bytes_test() {
  // <<0, 1>> → base64 "AAE="
  skir_client.to_dense_json(skir_client.bytes_serializer(), <<0, 1>>)
  |> should.equal("\"AAE=\"")
}

pub fn to_dense_json_three_bytes_test() {
  // <<0, 1, 2>> → base64 "AAEC"
  skir_client.to_dense_json(skir_client.bytes_serializer(), <<0, 1, 2>>)
  |> should.equal("\"AAEC\"")
}

pub fn to_dense_json_hello_test() {
  // "hello" in bytes → base64 "aGVsbG8="
  skir_client.to_dense_json(
    skir_client.bytes_serializer(),
    <<104, 101, 108, 108, 111>>,
  )
  |> should.equal("\"aGVsbG8=\"")
}

// =============================================================================
// to_readable_json   (hex: prefix)
// =============================================================================

pub fn to_readable_json_empty_bytes_test() {
  skir_client.to_readable_json(skir_client.bytes_serializer(), <<>>)
  |> should.equal("\"hex:\"")
}

pub fn to_readable_json_single_byte_test() {
  // <<0x0f>> → "hex:0f"
  skir_client.to_readable_json(skir_client.bytes_serializer(), <<15>>)
  |> should.equal("\"hex:0f\"")
}

pub fn to_readable_json_multiple_bytes_test() {
  // <<0xde, 0xad, 0xbe, 0xef>> → "hex:deadbeef"
  skir_client.to_readable_json(
    skir_client.bytes_serializer(),
    <<0xde, 0xad, 0xbe, 0xef>>,
  )
  |> should.equal("\"hex:deadbeef\"")
}

// =============================================================================
// from_json
// =============================================================================

pub fn from_json_base64_test() {
  skir_client.from_json(skir_client.bytes_serializer(), "\"aGVsbG8=\"")
  |> should.be_ok
  |> should.equal(<<104, 101, 108, 108, 111>>)
}

pub fn from_json_empty_base64_test() {
  skir_client.from_json(skir_client.bytes_serializer(), "\"\"")
  |> should.be_ok
  |> should.equal(<<>>)
}

pub fn from_json_null_yields_empty_bytes_test() {
  skir_client.from_json(skir_client.bytes_serializer(), "null")
  |> should.be_ok
  |> should.equal(<<>>)
}

pub fn from_json_number_yields_empty_bytes_test() {
  skir_client.from_json(skir_client.bytes_serializer(), "0")
  |> should.be_ok
  |> should.equal(<<>>)
}

pub fn from_json_hex_prefix_test() {
  skir_client.from_json(skir_client.bytes_serializer(), "\"hex:deadbeef\"")
  |> should.be_ok
  |> should.equal(<<0xde, 0xad, 0xbe, 0xef>>)
}

pub fn from_json_round_trip_dense_test() {
  let s = skir_client.bytes_serializer()
  let value = <<1, 2, 3, 4, 5>>
  skir_client.to_dense_json(s, value)
  |> skir_client.from_json(s, _)
  |> should.be_ok
  |> should.equal(value)
}

pub fn from_json_round_trip_readable_test() {
  let s = skir_client.bytes_serializer()
  let value = <<0xca, 0xfe, 0xba, 0xbe>>
  skir_client.to_readable_json(s, value)
  |> skir_client.from_json(s, _)
  |> should.be_ok
  |> should.equal(value)
}

// =============================================================================
// binary encoding
// =============================================================================

pub fn binary_encoding_empty_is_wire_244_test() {
  // empty → skir prefix + wire 244
  skir_client.to_bytes(skir_client.bytes_serializer(), <<>>)
  |> should.equal(<<115, 107, 105, 114, 244>>)
}

pub fn binary_encoding_hello_bytes_test() {
  // <<104,101,108,108,111>>, len=5
  // → skir + 245 + 5 + bytes
  skir_client.to_bytes(
    skir_client.bytes_serializer(),
    <<104, 101, 108, 108, 111>>,
  )
  |> should.equal(<<115, 107, 105, 114, 245, 5, 104, 101, 108, 108, 111>>)
}

// =============================================================================
// binary round-trip
// =============================================================================

pub fn binary_round_trip_empty_test() {
  let s = skir_client.bytes_serializer()
  skir_client.to_bytes(s, <<>>)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal(<<>>)
}

pub fn binary_round_trip_bytes_test() {
  let s = skir_client.bytes_serializer()
  let value = <<1, 2, 3, 4, 5, 255, 0, 127>>
  skir_client.to_bytes(s, value)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal(value)
}

// =============================================================================
// type_descriptor
// =============================================================================

pub fn type_descriptor_is_bytes_test() {
  let td = skir_client.type_descriptor(skir_client.bytes_serializer())
  let json = skir_client.type_descriptor_to_json(td)
  let expected =
    "{\n  \"type\": {\n    \"kind\": \"primitive\",\n    \"value\": \"bytes\"\n  },\n  \"records\": []\n}"
  should.equal(json, expected)
}
