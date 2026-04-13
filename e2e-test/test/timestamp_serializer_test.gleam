import gleeunit/should
import skir_client
import tempo/datetime as dt

// =============================================================================
// datetime_serializer — to_dense_json
// =============================================================================

pub fn datetime_to_dense_json_epoch_test() {
  let epoch = dt.from_unix_milli(0)
  skir_client.to_dense_json(skir_client.datetime_serializer(), epoch)
  |> should.equal("0")
}

pub fn datetime_to_dense_json_nonzero_test() {
  // 2009-02-13T23:31:30.000Z = 1234567890000 ms since epoch
  let d = dt.from_unix_milli(1_234_567_890_000)
  skir_client.to_dense_json(skir_client.datetime_serializer(), d)
  |> should.equal("1234567890000")
}

// =============================================================================
// datetime_serializer — to_readable_json
// =============================================================================

pub fn datetime_to_readable_json_epoch_test() {
  let epoch = dt.from_unix_milli(0)
  skir_client.to_readable_json(skir_client.datetime_serializer(), epoch)
  |> should.equal(
    "{\n  \"unix_millis\": 0,\n  \"formatted\": \"1970-01-01T00:00:00.000Z\"\n}",
  )
}

pub fn datetime_to_readable_json_nonzero_test() {
  let d = dt.from_unix_milli(1_234_567_890_000)
  skir_client.to_readable_json(skir_client.datetime_serializer(), d)
  |> should.equal(
    "{\n  \"unix_millis\": 1234567890000,\n  \"formatted\": \"2009-02-13T23:31:30.000Z\"\n}",
  )
}

// =============================================================================
// datetime_serializer — from_json
// =============================================================================

pub fn datetime_from_json_integer_test() {
  skir_client.from_json(skir_client.datetime_serializer(), "1234567890000")
  |> should.be_ok
  |> dt.to_unix_milli
  |> should.equal(1_234_567_890_000)
}

pub fn datetime_from_json_null_is_epoch_test() {
  skir_client.from_json(skir_client.datetime_serializer(), "null")
  |> should.be_ok
  |> dt.to_unix_milli
  |> should.equal(0)
}

pub fn datetime_from_json_object_test() {
  let json =
    "{\n  \"unix_millis\": 1234567890000,\n  \"formatted\": \"2009-02-13T23:31:30.000Z\"\n}"
  skir_client.from_json(skir_client.datetime_serializer(), json)
  |> should.be_ok
  |> dt.to_unix_milli
  |> should.equal(1_234_567_890_000)
}

pub fn datetime_from_json_quoted_millis_test() {
  skir_client.from_json(skir_client.datetime_serializer(), "\"1234567890000\"")
  |> should.be_ok
  |> dt.to_unix_milli
  |> should.equal(1_234_567_890_000)
}

// =============================================================================
// datetime_serializer — binary encoding
// =============================================================================

pub fn datetime_encode_epoch_is_single_byte_zero_test() {
  // "skir" (4 bytes) + wire 0 (1 byte) for epoch (ms = 0)
  let epoch = dt.from_unix_milli(0)
  skir_client.to_bytes(skir_client.datetime_serializer(), epoch)
  |> should.equal(<<115, 107, 105, 114, 0>>)
}

pub fn datetime_encode_nonzero_starts_with_wire_239_test() {
  // 1234567890000 is > i32 max so wire byte 239 (64-bit LE) is used
  let d = dt.from_unix_milli(1_234_567_890_000)
  let bytes = skir_client.to_bytes(skir_client.datetime_serializer(), d)
  case bytes {
    <<115, 107, 105, 114, 239, _:bits>> -> Nil
    _ -> should.fail()
  }
}

// =============================================================================
// datetime_serializer — binary round-trips
// =============================================================================

pub fn datetime_binary_round_trip_epoch_test() {
  let s = skir_client.datetime_serializer()
  let epoch = dt.from_unix_milli(0)
  skir_client.to_bytes(s, epoch)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> dt.to_unix_milli
  |> should.equal(0)
}

pub fn datetime_binary_round_trip_nonzero_test() {
  let s = skir_client.datetime_serializer()
  let ms = 1_234_567_890_000
  let d = dt.from_unix_milli(ms)
  skir_client.to_bytes(s, d)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> dt.to_unix_milli
  |> should.equal(ms)
}

pub fn datetime_binary_round_trip_small_millis_test() {
  let s = skir_client.datetime_serializer()
  let ms = 42
  let d = dt.from_unix_milli(ms)
  skir_client.to_bytes(s, d)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> dt.to_unix_milli
  |> should.equal(ms)
}
