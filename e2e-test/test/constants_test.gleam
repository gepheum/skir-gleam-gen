import gleeunit/should
import skirout/constants
import skirout/enums
import timestamp

// =============================================================================
// b_constant
// =============================================================================

pub fn b_constant_test() {
  constants.b_constant
  |> should.equal(False)
}

// =============================================================================
// foo_method_constant
// =============================================================================

pub fn foo_method_constant_test() {
  constants.foo_method_constant
  |> should.equal(True)
}

// =============================================================================
// large_int64_constant
// =============================================================================

pub fn large_int64_constant_test() {
  constants.large_int64_constant
  |> should.equal(9_223_372_036_854_775_807)
}

// =============================================================================
// one_single_quoted_string_constant
// =============================================================================

pub fn one_single_quoted_string_constant_test() {
  constants.one_single_quoted_string_constant
  |> should.equal("\"Foo\"")
}

// =============================================================================
// one_timestamp_constant
// =============================================================================

pub fn one_timestamp_constant_test() {
  let timestamp.Timestamp(unix_millis: ms) = constants.one_timestamp_constant
  ms
  |> should.equal(1_703_984_028_000)
}

// =============================================================================
// pi_constant
// =============================================================================

pub fn pi_constant_test() {
  constants.pi_constant
  |> should.equal(3.141592653589793)
}

// =============================================================================
// one_constant_constant — complex enum with nested values
// =============================================================================

pub fn one_constant_constant_is_array_variant_test() {
  case constants.one_constant_constant {
    enums.JsonValueArray(_) -> Nil
    _ -> should.fail()
  }
}

pub fn one_constant_constant_array_has_4_items_test() {
  let assert enums.JsonValueArray(items) = constants.one_constant_constant
  let assert [b, n, s, obj] = items
  b |> should.equal(enums.JsonValueBoolean(True))
  n |> should.equal(enums.JsonValueNumber(2.5))
  s |> should.equal(enums.JsonValueString("\n        foo\n        bar"))
  let assert enums.JsonValueObject([pair]) = obj
  let enums.JsonValuePair(name: name, value: v, ..) = pair
  name |> should.equal("foo")
  v |> should.equal(enums.JsonValueNull)
}

// =============================================================================
// infinity_constant, minus_infinity_constant, nan_constant — pub const fallbacks
// =============================================================================

pub fn infinity_constant_is_float_test() {
  // Infinity maps to max float
  should.equal(constants.infinity_constant >. 1.0e308, True)
}
