import gleam/option.{None, Some}
import gleeunit/should
import skir_client

// =============================================================================
// optional_serializer — to_dense_json
// =============================================================================

pub fn optional_to_dense_json_none_test() {
  skir_client.to_dense_json(
    skir_client.optional_serializer(skir_client.int32_serializer()),
    None,
  )
  |> should.equal("null")
}

pub fn optional_to_dense_json_some_test() {
  skir_client.to_dense_json(
    skir_client.optional_serializer(skir_client.int32_serializer()),
    Some(42),
  )
  |> should.equal("42")
}

// =============================================================================
// optional_serializer — to_readable_json
// =============================================================================

pub fn optional_to_readable_json_none_test() {
  skir_client.to_readable_json(
    skir_client.optional_serializer(skir_client.int32_serializer()),
    None,
  )
  |> should.equal("null")
}

pub fn optional_to_readable_json_some_test() {
  skir_client.to_readable_json(
    skir_client.optional_serializer(skir_client.int32_serializer()),
    Some(42),
  )
  |> should.equal("42")
}

// =============================================================================
// optional_serializer — from_json
// =============================================================================

pub fn optional_from_json_null_test() {
  skir_client.from_json(
    skir_client.optional_serializer(skir_client.int32_serializer()),
    "null",
  )
  |> should.be_ok
  |> should.equal(None)
}

pub fn optional_from_json_value_test() {
  skir_client.from_json(
    skir_client.optional_serializer(skir_client.int32_serializer()),
    "42",
  )
  |> should.be_ok
  |> should.equal(Some(42))
}

// =============================================================================
// optional_serializer — binary encoding
// =============================================================================

pub fn optional_encode_none_is_single_zero_byte_test() {
  // "skir" prefix (4 bytes) + 0x00 for None
  skir_client.to_bytes(
    skir_client.optional_serializer(skir_client.int32_serializer()),
    None,
  )
  |> should.equal(<<115, 107, 105, 114, 0>>)
}

pub fn optional_encode_some_starts_with_one_byte_test() {
  // "skir" prefix (4 bytes) + 0x01 tag + encoded value
  let bytes =
    skir_client.to_bytes(
      skir_client.optional_serializer(skir_client.int32_serializer()),
      Some(0),
    )
  case bytes {
    <<115, 107, 105, 114, 1, _:bits>> -> Nil
    _ -> should.fail()
  }
}

// =============================================================================
// optional_serializer — binary round-trips
// =============================================================================

pub fn optional_binary_round_trip_none_test() {
  let s = skir_client.optional_serializer(skir_client.int32_serializer())
  skir_client.to_bytes(s, None)
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal(None)
}

pub fn optional_binary_round_trip_some_test() {
  let s = skir_client.optional_serializer(skir_client.int32_serializer())
  skir_client.to_bytes(s, Some(42))
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal(Some(42))
}
