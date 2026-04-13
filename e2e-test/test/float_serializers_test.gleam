import gleeunit/should
import skir_client

// =============================================================================
// float32_serializer — to_dense_json
// =============================================================================

pub fn float32_to_dense_json_zero_test() {
  skir_client.to_dense_json(skir_client.float32_serializer(), 0.0)
  |> should.equal("0")
}

pub fn float32_to_dense_json_one_test() {
  skir_client.to_dense_json(skir_client.float32_serializer(), 1.0)
  |> should.equal("1")
}

pub fn float32_to_dense_json_one_and_half_test() {
  skir_client.to_dense_json(skir_client.float32_serializer(), 1.5)
  |> should.equal("1.5")
}

pub fn float32_to_dense_json_negative_test() {
  skir_client.to_dense_json(skir_client.float32_serializer(), -3.14)
  |> should.equal("-3.14")
}

// =============================================================================
// float32_serializer — to_readable_json (identical to dense for scalars)
// =============================================================================

pub fn float32_to_readable_json_zero_test() {
  skir_client.to_readable_json(skir_client.float32_serializer(), 0.0)
  |> should.equal("0")
}

pub fn float32_to_readable_json_nonzero_test() {
  skir_client.to_readable_json(skir_client.float32_serializer(), 1.5)
  |> should.equal("1.5")
}

// =============================================================================
// float32_serializer — from_json
// =============================================================================

pub fn float32_from_json_number_test() {
  skir_client.from_json(skir_client.float32_serializer(), "1.5")
  |> should.be_ok
  |> should.equal(1.5)
}

pub fn float32_from_json_integer_test() {
  skir_client.from_json(skir_client.float32_serializer(), "3")
  |> should.be_ok
  |> should.equal(3.0)
}

pub fn float32_from_json_null_is_zero_test() {
  skir_client.from_json(skir_client.float32_serializer(), "null")
  |> should.be_ok
  |> should.equal(0.0)
}

pub fn float32_from_json_quoted_string_test() {
  skir_client.from_json(skir_client.float32_serializer(), "\"1.5\"")
  |> should.be_ok
  |> should.equal(1.5)
}

// =============================================================================
// float32_serializer — binary encoding
// =============================================================================

pub fn float32_encode_zero_is_single_byte_zero_test() {
  // "skir" magic (4 bytes) + wire 0 (1 byte)
  skir_client.to_bytes(skir_client.float32_serializer(), 0.0)
  |> should.equal(<<115, 107, 105, 114, 0>>)
}

pub fn float32_encode_nonzero_starts_with_wire_240_test() {
  let bytes = skir_client.to_bytes(skir_client.float32_serializer(), 1.5)
  // "skir" is 4 bytes, then wire byte 240
  case bytes {
    <<115, 107, 105, 114, 240, _:bits>> -> Nil
    _ -> should.fail()
  }
}

// =============================================================================
// float32_serializer — binary round-trips (exact float32 values)
// =============================================================================

pub fn float32_binary_round_trip_zero_test() {
  let s = skir_client.float32_serializer()
  let value = 0.0
  skir_client.to_bytes(s, value)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal(value)
}

pub fn float32_binary_round_trip_one_and_half_test() {
  let s = skir_client.float32_serializer()
  let value = 1.5
  skir_client.to_bytes(s, value)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal(value)
}

pub fn float32_binary_round_trip_negative_test() {
  let s = skir_client.float32_serializer()
  let value = -1.5
  skir_client.to_bytes(s, value)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal(value)
}

// =============================================================================
// float64_serializer — to_dense_json
// =============================================================================

pub fn float64_to_dense_json_zero_test() {
  skir_client.to_dense_json(skir_client.float64_serializer(), 0.0)
  |> should.equal("0")
}

pub fn float64_to_dense_json_one_test() {
  skir_client.to_dense_json(skir_client.float64_serializer(), 1.0)
  |> should.equal("1")
}

pub fn float64_to_dense_json_one_and_half_test() {
  skir_client.to_dense_json(skir_client.float64_serializer(), 1.5)
  |> should.equal("1.5")
}

pub fn float64_to_dense_json_negative_test() {
  skir_client.to_dense_json(skir_client.float64_serializer(), -3.14)
  |> should.equal("-3.14")
}

// =============================================================================
// float64_serializer — to_readable_json
// =============================================================================

pub fn float64_to_readable_json_zero_test() {
  skir_client.to_readable_json(skir_client.float64_serializer(), 0.0)
  |> should.equal("0")
}

pub fn float64_to_readable_json_nonzero_test() {
  skir_client.to_readable_json(skir_client.float64_serializer(), 1.5)
  |> should.equal("1.5")
}

// =============================================================================
// float64_serializer — from_json
// =============================================================================

pub fn float64_from_json_number_test() {
  skir_client.from_json(skir_client.float64_serializer(), "1.5")
  |> should.be_ok
  |> should.equal(1.5)
}

pub fn float64_from_json_integer_test() {
  skir_client.from_json(skir_client.float64_serializer(), "3")
  |> should.be_ok
  |> should.equal(3.0)
}

pub fn float64_from_json_null_is_zero_test() {
  skir_client.from_json(skir_client.float64_serializer(), "null")
  |> should.be_ok
  |> should.equal(0.0)
}

pub fn float64_from_json_quoted_string_test() {
  skir_client.from_json(skir_client.float64_serializer(), "\"1.5\"")
  |> should.be_ok
  |> should.equal(1.5)
}

// =============================================================================
// float64_serializer — binary encoding
// =============================================================================

pub fn float64_encode_zero_is_single_byte_zero_test() {
  skir_client.to_bytes(skir_client.float64_serializer(), 0.0)
  |> should.equal(<<115, 107, 105, 114, 0>>)
}

pub fn float64_encode_nonzero_starts_with_wire_241_test() {
  let bytes = skir_client.to_bytes(skir_client.float64_serializer(), 1.5)
  case bytes {
    <<115, 107, 105, 114, 241, _:bits>> -> Nil
    _ -> should.fail()
  }
}

// =============================================================================
// float64_serializer — binary round-trips
// =============================================================================

pub fn float64_binary_round_trip_zero_test() {
  let s = skir_client.float64_serializer()
  let value = 0.0
  skir_client.to_bytes(s, value)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal(value)
}

pub fn float64_binary_round_trip_nonzero_test() {
  let s = skir_client.float64_serializer()
  let value = 3.141_592_653_589_793
  skir_client.to_bytes(s, value)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal(value)
}

pub fn float64_binary_round_trip_negative_test() {
  let s = skir_client.float64_serializer()
  let value = -2.718_281_828_459_045
  skir_client.to_bytes(s, value)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal(value)
}
