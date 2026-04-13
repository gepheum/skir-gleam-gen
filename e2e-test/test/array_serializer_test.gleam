import gleeunit/should
import skir_client

// =============================================================================
// list_serializer — to_dense_json
// =============================================================================

pub fn array_to_dense_json_empty_test() {
  skir_client.to_dense_json(
    skir_client.list_serializer(skir_client.int32_serializer()),
    [],
  )
  |> should.equal("[]")
}

pub fn array_to_dense_json_nonempty_test() {
  skir_client.to_dense_json(
    skir_client.list_serializer(skir_client.int32_serializer()),
    [1, 2, 3],
  )
  |> should.equal("[1,2,3]")
}

// =============================================================================
// list_serializer — to_readable_json
// =============================================================================

pub fn array_to_readable_json_empty_test() {
  skir_client.to_readable_json(
    skir_client.list_serializer(skir_client.int32_serializer()),
    [],
  )
  |> should.equal("[]")
}

pub fn array_to_readable_json_nonempty_test() {
  skir_client.to_readable_json(
    skir_client.list_serializer(skir_client.int32_serializer()),
    [1, 2],
  )
  |> should.equal("[\n  1,\n  2\n]")
}

// =============================================================================
// list_serializer — from_json
// =============================================================================

pub fn array_from_json_empty_test() {
  skir_client.from_json(
    skir_client.list_serializer(skir_client.int32_serializer()),
    "[]",
  )
  |> should.be_ok
  |> should.equal([])
}

pub fn array_from_json_nonempty_test() {
  skir_client.from_json(
    skir_client.list_serializer(skir_client.int32_serializer()),
    "[1,2,3]",
  )
  |> should.be_ok
  |> should.equal([1, 2, 3])
}

// =============================================================================
// list_serializer — binary round-trips
// =============================================================================

pub fn array_binary_round_trip_empty_test() {
  let s = skir_client.list_serializer(skir_client.int32_serializer())
  skir_client.to_bytes(s, [])
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal([])
}

pub fn array_binary_round_trip_nonempty_test() {
  let s = skir_client.list_serializer(skir_client.int32_serializer())
  skir_client.to_bytes(s, [1, 2, 3])
  |> skir_client.from_bytes(s, _)
  |> should.be_ok
  |> should.equal([1, 2, 3])
}
