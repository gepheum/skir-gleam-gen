import gleam/option.{type Option}

// =============================================================================
// UnrecognizedFormat
// =============================================================================

/// The serialization format used to capture unrecognized data.
pub type UnrecognizedFormat {
  DenseJson
  BinaryBytes
}

// =============================================================================
// UnrecognizedFieldsData
// =============================================================================

/// Internal data holding unrecognized struct fields encountered during
/// deserialization.
///
/// The type parameter `t` ties this value to the struct type it belongs to,
/// even though no value of type `t` is actually stored here (phantom type).
pub opaque type UnrecognizedFieldsData(t) {
  UnrecognizedFieldsData(
    format: UnrecognizedFormat,
    /// Full slot count (recognized + unrecognized) of the source JSON array or
    /// binary struct.
    array_len: Int,
    /// Raw bytes of the unrecognized field values.
    values: BitArray,
    phantom_t: List(t),
  )
}

/// Creates an `UnrecognizedFieldsData` carrying extra JSON slots from a dense
/// JSON array. `array_len` is the full slot count (recognized + unrecognized);
/// `json_bytes` is the serialized JSON of the extra elements as a JSON array
/// string (e.g. `"[1,\"foo\"]"`).
pub fn fields_data_from_json(
  array_len: Int,
  json_bytes: BitArray,
) -> UnrecognizedFieldsData(t) {
  UnrecognizedFieldsData(
    format: DenseJson,
    array_len:,
    values: json_bytes,
    phantom_t: [],
  )
}

/// Creates an `UnrecognizedFieldsData` carrying raw binary wire bytes for
/// extra slots from a binary-encoded struct.
pub fn fields_data_from_bytes(
  array_len: Int,
  raw_bytes: BitArray,
) -> UnrecognizedFieldsData(t) {
  UnrecognizedFieldsData(
    format: BinaryBytes,
    array_len:,
    values: raw_bytes,
    phantom_t: [],
  )
}

pub fn fields_data_format(data: UnrecognizedFieldsData(t)) -> UnrecognizedFormat {
  data.format
}

pub fn fields_data_array_len(data: UnrecognizedFieldsData(t)) -> Int {
  data.array_len
}

pub fn fields_data_values(data: UnrecognizedFieldsData(t)) -> BitArray {
  data.values
}

// =============================================================================
// UnrecognizedVariantData
// =============================================================================

/// Holds an unrecognized enum variant encountered during deserialization.
///
/// The type parameter `t` ties this value to the enum type it belongs to,
/// even though no value of type `t` is actually stored here (phantom type).
pub opaque type UnrecognizedVariantData(t) {
  UnrecognizedVariantData(
    format: UnrecognizedFormat,
    /// Wire number of the unrecognized variant.
    number: Int,
    /// Empty if the unrecognized variant is a constant variant (number).
    value: BitArray,
    phantom_t: List(t),
  )
}

/// Creates an `UnrecognizedVariantData` for an unrecognized constant variant
/// from a binary-encoded context. `raw_bytes` is the re-encoded number.
pub fn variant_data_from_bytes(
  number: Int,
  raw_bytes: BitArray,
) -> UnrecognizedVariantData(t) {
  UnrecognizedVariantData(
    format: BinaryBytes,
    number:,
    value: raw_bytes,
    phantom_t: [],
  )
}

/// Creates an `UnrecognizedVariantData` for an unrecognized variant carrying
/// a JSON-encoded value (wrapper variant or raw JSON element).
pub fn variant_data_from_json(
  number: Int,
  json_bytes: BitArray,
) -> UnrecognizedVariantData(t) {
  UnrecognizedVariantData(
    format: DenseJson,
    number:,
    value: json_bytes,
    phantom_t: [],
  )
}

pub fn variant_data_format(
  data: UnrecognizedVariantData(t),
) -> UnrecognizedFormat {
  data.format
}

pub fn variant_data_number(data: UnrecognizedVariantData(t)) -> Int {
  data.number
}

pub fn variant_data_value(data: UnrecognizedVariantData(t)) -> BitArray {
  data.value
}

// =============================================================================
// UnrecognizedFields / UnrecognizedVariant
// =============================================================================

/// Stores unrecognized fields encountered while deserializing a struct of type
/// `t`. `None` when deserialization was performed without keeping unrecognized
/// values.
pub type UnrecognizedFields(t) =
  Option(UnrecognizedFieldsData(t))

/// Stores an unrecognized variant encountered while deserializing an enum of
/// type `t`.
pub type UnrecognizedVariant(t) =
  Option(UnrecognizedVariantData(t))
