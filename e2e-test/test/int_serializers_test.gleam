import gleeunit/should
import skir_client

// =============================================================================
// int32_serializer — to_json
// =============================================================================

pub fn int32_to_json_zero_test() {
  skir_client.to_dense_json(skir_client.int32_serializer(), 0)
  |> should.equal("0")
}

pub fn int32_to_json_positive_test() {
  skir_client.to_dense_json(skir_client.int32_serializer(), 42)
  |> should.equal("42")
}

pub fn int32_to_json_negative_test() {
  skir_client.to_dense_json(skir_client.int32_serializer(), -1)
  |> should.equal("-1")
}

pub fn int32_to_json_same_in_readable_mode_test() {
  let s = skir_client.int32_serializer()
  skir_client.to_dense_json(s, 12_345)
  |> should.equal(skir_client.to_readable_json(s, 12_345))
}

// =============================================================================
// int32_serializer — from_json
// =============================================================================

pub fn int32_from_json_integer_test() {
  let s = skir_client.int32_serializer()
  skir_client.from_json(s, "42") |> should.be_ok |> should.equal(42)
  skir_client.from_json(s, "-1") |> should.be_ok |> should.equal(-1)
  skir_client.from_json(s, "0") |> should.be_ok |> should.equal(0)
}

pub fn int32_from_json_float_truncates_test() {
  let s = skir_client.int32_serializer()
  skir_client.from_json(s, "3.9") |> should.be_ok |> should.equal(3)
  skir_client.from_json(s, "-1.5") |> should.be_ok |> should.equal(-1)
}

pub fn int32_from_json_string_test() {
  skir_client.from_json(skir_client.int32_serializer(), "\"7\"")
  |> should.be_ok
  |> should.equal(7)
}

pub fn int32_from_json_unparseable_string_is_zero_test() {
  skir_client.from_json(skir_client.int32_serializer(), "\"abc\"")
  |> should.be_ok
  |> should.equal(0)
}

pub fn int32_from_json_null_is_zero_test() {
  skir_client.from_json(skir_client.int32_serializer(), "null")
  |> should.be_ok
  |> should.equal(0)
}

// =============================================================================
// int32_serializer — binary encoding
// =============================================================================

pub fn int32_encode_small_positive_is_single_byte_test() {
  let s = skir_client.int32_serializer()
  skir_client.to_bytes(s, 0) |> should.equal(<<115, 107, 105, 114, 0>>)
  skir_client.to_bytes(s, 1) |> should.equal(<<115, 107, 105, 114, 1>>)
  skir_client.to_bytes(s, 231) |> should.equal(<<115, 107, 105, 114, 231>>)
}

pub fn int32_encode_u16_range_test() {
  // 1000 = 0x03E8, LE: 232, 3
  let bytes = skir_client.to_bytes(skir_client.int32_serializer(), 1000)
  should.equal(bytes, <<115, 107, 105, 114, 232, 232, 3>>)
}

pub fn int32_encode_u32_range_test() {
  // 65536: wire 233, u32 LE: 0, 0, 1, 0
  let bytes = skir_client.to_bytes(skir_client.int32_serializer(), 65_536)
  should.equal(bytes, <<115, 107, 105, 114, 233, 0, 0, 1, 0>>)
}

pub fn int32_encode_small_negative_test() {
  // -1: wire 235, then (-1 + 256) = 255
  let bytes = skir_client.to_bytes(skir_client.int32_serializer(), -1)
  should.equal(bytes, <<115, 107, 105, 114, 235, 255>>)
}

pub fn int32_encode_medium_negative_test() {
  // -300: wire 236, then (-300 + 65536) = 65236 = 0xFED4 LE: 212, 254
  let bytes = skir_client.to_bytes(skir_client.int32_serializer(), -300)
  should.equal(bytes, <<115, 107, 105, 114, 236, 212, 254>>)
}

pub fn int32_encode_large_negative_test() {
  // -100_000: wire 237, then i32 LE bytes of -100000
  // -100000 as u32 = 4294867296 = 0xFFFE7960, LE: 96, 121, 254, 255
  let bytes = skir_client.to_bytes(skir_client.int32_serializer(), -100_000)
  should.equal(bytes, <<115, 107, 105, 114, 237, 96, 121, 254, 255>>)
}

pub fn int32_binary_round_trip_test() {
  let s = skir_client.int32_serializer()
  let values = [
    0,
    1,
    42,
    231,
    232,
    300,
    65_535,
    65_536,
    -1,
    -255,
    -256,
    -65_536,
  ]
  values
  |> list_each(fn(v) {
    skir_client.from_bytes(s, skir_client.to_bytes(s, v))
    |> should.be_ok
    |> should.equal(v)
  })
}

// =============================================================================
// int32_serializer — type_descriptor
// =============================================================================

pub fn int32_type_descriptor_test() {
  let td = skir_client.type_descriptor(skir_client.int32_serializer())
  let json = skir_client.type_descriptor_to_json(td)
  let expected =
    "{\n  \"type\": {\n    \"kind\": \"primitive\",\n    \"value\": \"int32\"\n  },\n  \"records\": []\n}"
  should.equal(json, expected)
}

// =============================================================================
// int64_serializer — to_json
// =============================================================================

pub fn int64_to_json_safe_integer_test() {
  let s = skir_client.int64_serializer()
  skir_client.to_dense_json(s, 0) |> should.equal("0")
  skir_client.to_dense_json(s, 9_007_199_254_740_991)
  |> should.equal("9007199254740991")
  skir_client.to_dense_json(s, -9_007_199_254_740_991)
  |> should.equal("-9007199254740991")
}

pub fn int64_to_json_large_value_is_quoted_test() {
  let s = skir_client.int64_serializer()
  skir_client.to_dense_json(s, 9_007_199_254_740_992)
  |> should.equal("\"9007199254740992\"")
  skir_client.to_dense_json(s, -9_007_199_254_740_992)
  |> should.equal("\"-9007199254740992\"")
}

// =============================================================================
// int64_serializer — from_json
// =============================================================================

pub fn int64_from_json_integer_test() {
  let s = skir_client.int64_serializer()
  skir_client.from_json(s, "42") |> should.be_ok |> should.equal(42)
  skir_client.from_json(s, "-1") |> should.be_ok |> should.equal(-1)
}

pub fn int64_from_json_quoted_large_test() {
  skir_client.from_json(skir_client.int64_serializer(), "\"9007199254740992\"")
  |> should.be_ok
  |> should.equal(9_007_199_254_740_992)
}

pub fn int64_from_json_null_is_zero_test() {
  skir_client.from_json(skir_client.int64_serializer(), "null")
  |> should.be_ok
  |> should.equal(0)
}

// =============================================================================
// int64_serializer — binary encoding
// =============================================================================

pub fn int64_encode_fits_i32_reuses_i32_encoding_test() {
  let s = skir_client.int64_serializer()
  skir_client.to_bytes(s, 0) |> should.equal(<<115, 107, 105, 114, 0>>)
  skir_client.to_bytes(s, 42) |> should.equal(<<115, 107, 105, 114, 42>>)
}

pub fn int64_encode_wire_238_test() {
  // 2147483648 = i32::MAX + 1 → wire 238 + i64 LE
  let v = 2_147_483_648
  let bytes = skir_client.to_bytes(skir_client.int64_serializer(), v)
  // wire 238 then 8 bytes LE: 0, 0, 0, 128, 0, 0, 0, 0
  should.equal(bytes, <<115, 107, 105, 114, 238, 0, 0, 0, 128, 0, 0, 0, 0>>)
}

pub fn int64_binary_round_trip_test() {
  let s = skir_client.int64_serializer()
  let values = [
    0, 1, 231, 232, 65_536, 2_147_483_647, 2_147_483_648, 9_007_199_254_740_991,
    -1, -2_147_483_648,
  ]
  values
  |> list_each(fn(v) {
    skir_client.from_bytes(s, skir_client.to_bytes(s, v))
    |> should.be_ok
    |> should.equal(v)
  })
}

// =============================================================================
// int64_serializer — type_descriptor
// =============================================================================

pub fn int64_type_descriptor_test() {
  let td = skir_client.type_descriptor(skir_client.int64_serializer())
  let json = skir_client.type_descriptor_to_json(td)
  let expected =
    "{\n  \"type\": {\n    \"kind\": \"primitive\",\n    \"value\": \"int64\"\n  },\n  \"records\": []\n}"
  should.equal(json, expected)
}

// =============================================================================
// hash64_serializer — to_json
// =============================================================================

pub fn hash64_to_json_safe_integer_test() {
  let s = skir_client.hash64_serializer()
  skir_client.to_dense_json(s, 0) |> should.equal("0")
  skir_client.to_dense_json(s, 9_007_199_254_740_991)
  |> should.equal("9007199254740991")
}

pub fn hash64_to_json_large_value_is_quoted_test() {
  skir_client.to_dense_json(
    skir_client.hash64_serializer(),
    9_007_199_254_740_992,
  )
  |> should.equal("\"9007199254740992\"")
}

// =============================================================================
// hash64_serializer — from_json
// =============================================================================

pub fn hash64_from_json_integer_test() {
  skir_client.from_json(skir_client.hash64_serializer(), "42")
  |> should.be_ok
  |> should.equal(42)
}

pub fn hash64_from_json_negative_number_is_zero_test() {
  skir_client.from_json(skir_client.hash64_serializer(), "-1.0")
  |> should.be_ok
  |> should.equal(0)
}

pub fn hash64_from_json_quoted_large_test() {
  skir_client.from_json(skir_client.hash64_serializer(), "\"9007199254740992\"")
  |> should.be_ok
  |> should.equal(9_007_199_254_740_992)
}

pub fn hash64_from_json_null_is_zero_test() {
  skir_client.from_json(skir_client.hash64_serializer(), "null")
  |> should.be_ok
  |> should.equal(0)
}

// =============================================================================
// hash64_serializer — binary encoding
// =============================================================================

pub fn hash64_encode_single_byte_range_test() {
  let s = skir_client.hash64_serializer()
  skir_client.to_bytes(s, 0) |> should.equal(<<115, 107, 105, 114, 0>>)
  skir_client.to_bytes(s, 231) |> should.equal(<<115, 107, 105, 114, 231>>)
}

pub fn hash64_encode_u16_range_test() {
  // 1000 = 0x03E8 LE: 232, 3
  let bytes = skir_client.to_bytes(skir_client.hash64_serializer(), 1000)
  should.equal(bytes, <<115, 107, 105, 114, 232, 232, 3>>)
}

pub fn hash64_encode_u32_range_test() {
  // 65536 LE: 0, 0, 1, 0
  let bytes = skir_client.to_bytes(skir_client.hash64_serializer(), 65_536)
  should.equal(bytes, <<115, 107, 105, 114, 233, 0, 0, 1, 0>>)
}

pub fn hash64_encode_u64_range_test() {
  // 4_294_967_296 = 2^32; wire 234 + u64 LE
  let v = 4_294_967_296
  let bytes = skir_client.to_bytes(skir_client.hash64_serializer(), v)
  should.equal(bytes, <<115, 107, 105, 114, 234, 0, 0, 0, 0, 1, 0, 0, 0>>)
}

pub fn hash64_binary_round_trip_test() {
  let s = skir_client.hash64_serializer()
  let values = [0, 1, 231, 232, 65_535, 65_536, 4_294_967_295, 4_294_967_296]
  values
  |> list_each(fn(v) {
    skir_client.from_bytes(s, skir_client.to_bytes(s, v))
    |> should.be_ok
    |> should.equal(v)
  })
}

// =============================================================================
// hash64_serializer — type_descriptor
// =============================================================================

pub fn hash64_type_descriptor_test() {
  let td = skir_client.type_descriptor(skir_client.hash64_serializer())
  let json = skir_client.type_descriptor_to_json(td)
  let expected =
    "{\n  \"type\": {\n    \"kind\": \"primitive\",\n    \"value\": \"hash64\"\n  },\n  \"records\": []\n}"
  should.equal(json, expected)
}

// =============================================================================
// Helpers
// =============================================================================

fn list_each(list: List(a), f: fn(a) -> Nil) -> Nil {
  case list {
    [] -> Nil
    [first, ..rest] -> {
      f(first)
      list_each(rest, f)
    }
  }
}
