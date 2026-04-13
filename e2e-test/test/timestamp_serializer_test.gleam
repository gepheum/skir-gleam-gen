import gleam/time/timestamp.{type Timestamp}
import gleeunit/should
import skir_client

fn from_unix_milli(ms: Int) -> Timestamp {
  timestamp.from_unix_seconds_and_nanoseconds(
    seconds: ms / 1000,
    nanoseconds: ms % 1000 * 1_000_000,
  )
}

fn to_unix_milli(ts: Timestamp) -> Int {
  let #(s, ns) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  s * 1000 + ns / 1_000_000
}

// =============================================================================
// timestamp_serializer — to_dense_json
// =============================================================================

pub fn timestamp_to_dense_json_epoch_test() {
  let epoch = from_unix_milli(0)
  skir_client.to_dense_json(skir_client.timestamp_serializer(), epoch)
  |> should.equal("0")
}

pub fn timestamp_to_dense_json_nonzero_test() {
  // 2009-02-13T23:31:30Z = 1234567890000 ms since epoch
  let d = from_unix_milli(1_234_567_890_000)
  skir_client.to_dense_json(skir_client.timestamp_serializer(), d)
  |> should.equal("1234567890000")
}

// =============================================================================
// timestamp_serializer — to_readable_json
// =============================================================================

pub fn timestamp_to_readable_json_epoch_test() {
  let epoch = from_unix_milli(0)
  skir_client.to_readable_json(skir_client.timestamp_serializer(), epoch)
  |> should.equal(
    "{\n  \"unix_millis\": 0,\n  \"formatted\": \"1970-01-01T00:00:00Z\"\n}",
  )
}

pub fn timestamp_to_readable_json_nonzero_test() {
  let d = from_unix_milli(1_234_567_890_000)
  skir_client.to_readable_json(skir_client.timestamp_serializer(), d)
  |> should.equal(
    "{\n  \"unix_millis\": 1234567890000,\n  \"formatted\": \"2009-02-13T23:31:30Z\"\n}",
  )
}

// =============================================================================
// timestamp_serializer — from_json
// =============================================================================

pub fn timestamp_from_json_integer_test() {
  skir_client.from_json(skir_client.timestamp_serializer(), "1234567890000")
  |> should.be_ok
  |> to_unix_milli
  |> should.equal(1_234_567_890_000)
}

pub fn timestamp_from_json_null_is_epoch_test() {
  skir_client.from_json(skir_client.timestamp_serializer(), "null")
  |> should.be_ok
  |> to_unix_milli
  |> should.equal(0)
}

pub fn timestamp_from_json_object_test() {
  let json =
    "{\n  \"unix_millis\": 1234567890000,\n  \"formatted\": \"2009-02-13T23:31:30Z\"\n}"
  skir_client.from_json(skir_client.timestamp_serializer(), json)
  |> should.be_ok
  |> to_unix_milli
  |> should.equal(1_234_567_890_000)
}

pub fn timestamp_from_json_quoted_millis_test() {
  skir_client.from_json(skir_client.timestamp_serializer(), "\"1234567890000\"")
  |> should.be_ok
  |> to_unix_milli
  |> should.equal(1_234_567_890_000)
}

// =============================================================================
// timestamp_serializer — binary encoding
// =============================================================================

pub fn timestamp_encode_epoch_is_single_byte_zero_test() {
  // "skir" (4 bytes) + wire 0 (1 byte) for epoch (ms = 0)
  let epoch = from_unix_milli(0)
  skir_client.to_bytes(skir_client.timestamp_serializer(), epoch)
  |> should.equal(<<115, 107, 105, 114, 0>>)
}

pub fn timestamp_encode_nonzero_starts_with_wire_239_test() {
  // 1234567890000 is > i32 max so wire byte 239 (64-bit LE) is used
  let d = from_unix_milli(1_234_567_890_000)
  let bytes = skir_client.to_bytes(skir_client.timestamp_serializer(), d)
  case bytes {
    <<115, 107, 105, 114, 239, _:bits>> -> Nil
    _ -> should.fail()
  }
}

// =============================================================================
// timestamp_serializer — binary round-trips
// =============================================================================

pub fn timestamp_binary_round_trip_epoch_test() {
  let s = skir_client.timestamp_serializer()
  let epoch = from_unix_milli(0)
  skir_client.to_bytes(s, epoch)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> to_unix_milli
  |> should.equal(0)
}

pub fn timestamp_binary_round_trip_nonzero_test() {
  let s = skir_client.timestamp_serializer()
  let ms = 1_234_567_890_000
  let d = from_unix_milli(ms)
  skir_client.to_bytes(s, d)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> to_unix_milli
  |> should.equal(ms)
}

pub fn timestamp_binary_round_trip_small_millis_test() {
  let s = skir_client.timestamp_serializer()
  let ms = 42
  let d = from_unix_milli(ms)
  skir_client.to_bytes(s, d)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> to_unix_milli
  |> should.equal(ms)
}
