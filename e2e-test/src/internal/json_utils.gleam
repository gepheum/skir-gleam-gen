import gleam/dynamic/decode

pub fn decode_errors_to_string(errors: List(decode.DecodeError)) -> String {
  case errors {
    [decode.DecodeError(expected:, found:, ..), ..] ->
      "expected " <> expected <> " but found " <> found
    _ -> "decode error"
  }
}
