import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import internal/json_utils
import internal/method.{type Method}
import serializer
import type_descriptor

// =============================================================================
// ServiceError
// =============================================================================

/// A controlled error that is sent back to the caller as a non-2xx HTTP
/// response.  Use this in your method implementations to signal expected
/// failures (e.g. "not found", "permission denied").
pub type HttpErrorCode {
  E400xBadRequest
  E401xUnauthorized
  E402xPaymentRequired
  E403xForbidden
  E404xNotFound
  E405xMethodNotAllowed
  E406xNotAcceptable
  E407xProxyAuthenticationRequired
  E408xRequestTimeout
  E409xConflict
  E410xGone
  E411xLengthRequired
  E412xPreconditionFailed
  E413xContentTooLarge
  E414xUriTooLong
  E415xUnsupportedMediaType
  E416xRangeNotSatisfiable
  E417xExpectationFailed
  E418xImATeapot
  E421xMisdirectedRequest
  E422xUnprocessableContent
  E423xLocked
  E424xFailedDependency
  E425xTooEarly
  E426xUpgradeRequired
  E428xPreconditionRequired
  E429xTooManyRequests
  E431xRequestHeaderFieldsTooLarge
  E451xUnavailableForLegalReasons
  E500xInternalServerError
  E501xNotImplemented
  E502xBadGateway
  E503xServiceUnavailable
  E504xGatewayTimeout
  E505xHttpVersionNotSupported
  E506xVariantAlsoNegotiates
  E507xInsufficientStorage
  E508xLoopDetected
  E510xNotExtended
  E511xNetworkAuthenticationRequired
}

pub type ServiceError {
  /// A controlled error with an explicit HTTP status code and message.
  /// Use this to signal expected failures (e.g. not found, permission denied).
  ServiceError(status: HttpErrorCode, message: String)
  /// An unexpected internal error. The message is only forwarded to the client
  /// if can_send_unknown_error_message is enabled on the service.
  UnknownError(message: String)
}

// =============================================================================
// RawResponse
// =============================================================================

/// The return value of handle_request.
pub type RawResponse {
  RawResponse(status_code: Int, content_type: String, data: String)
}

// =============================================================================
// ErrorInfo
// =============================================================================

pub type ServiceErrorInfo(meta, state) {
  ErrorInfo(
    error: ServiceError,
    message: String,
    method_name: String,
    request_meta: meta,
    state: state,
  )
}

// =============================================================================
// Internal: type-erased method
// =============================================================================

type InvokeFn(meta, state, message) =
  fn(dynamic.Dynamic, Bool, Bool, meta, state) ->
    #(Result(String, ServiceError), meta, message)

type ErasedMethod(meta, state, message) {
  ErasedMethod(
    name: String,
    number: Int,
    doc: String,
    request_type_descriptor_json: String,
    response_type_descriptor_json: String,
    invoke: InvokeFn(meta, state, message),
  )
}

fn make_erased_method(
  method: Method(req, resp),
  empty_message: message,
  handler: fn(req, meta, state) -> #(Result(resp, ServiceError), meta, message),
) -> ErasedMethod(meta, state, message) {
  let request_td_json =
    method.request_serializer
    |> serializer.type_descriptor()
    |> type_descriptor.type_descriptor_to_json()
  let response_td_json =
    method.response_serializer
    |> serializer.type_descriptor()
    |> type_descriptor.type_descriptor_to_json()

  let invoke = fn(request_dynamic, keep_bool, readable, meta, state) {
    case
      decode.run(
        request_dynamic,
        serializer.json_decoder_with_options(
          method.request_serializer,
          keep_unrecognized_values: keep_bool,
        ),
      )
    {
      Error(errors) -> #(
        Error(ServiceError(
          status: E400xBadRequest,
          message: "bad request: " <> json_utils.decode_errors_to_string(errors),
        )),
        meta,
        empty_message,
      )
      Ok(req) ->
        case handler(req, meta, state) {
          #(Error(e), new_meta, new_state) -> #(Error(e), new_meta, new_state)
          #(Ok(response_value), new_meta, new_state) -> {
            let json_str = case readable {
              True ->
                serializer.to_readable_json_code(
                  method.response_serializer,
                  response_value,
                )
              False ->
                serializer.to_dense_json_code(
                  method.response_serializer,
                  response_value,
                )
            }
            #(Ok(json_str), new_meta, new_state)
          }
        }
    }
  }

  ErasedMethod(
    name: method.name,
    number: method.number,
    doc: method.doc,
    request_type_descriptor_json: request_td_json,
    response_type_descriptor_json: response_td_json,
    invoke: invoke,
  )
}

// =============================================================================
// Service
// =============================================================================

pub opaque type Service(meta, state, message) {
  Service(
    keep_unrecognized: Bool,
    can_send_unknown_error_message: fn(ServiceErrorInfo(meta, state)) -> Bool,
    error_logger: fn(ServiceErrorInfo(meta, state)) -> Nil,
    empty_message: message,
    studio_url: String,
    by_number: Dict(Int, ErasedMethod(meta, state, message)),
    by_name: Dict(String, ErasedMethod(meta, state, message)),
  )
}

// =============================================================================
// Service setup
// =============================================================================

pub fn new(
  empty_message empty_message: message,
) -> Service(meta, state, message) {
  Service(
    keep_unrecognized: False,
    can_send_unknown_error_message: fn(_info) { False },
    error_logger: noop_error_logger,
    empty_message: empty_message,
    studio_url: default_studio_url,
    by_number: dict.new(),
    by_name: dict.new(),
  )
}

pub fn add_method(
  service: Service(meta, state, message),
  method: Method(req, resp),
  handler: fn(req, meta, state) -> #(Result(resp, ServiceError), meta, message),
) -> Service(meta, state, message) {
  let erased = make_erased_method(method, service.empty_message, handler)
  Service(
    ..service,
    by_number: dict.insert(service.by_number, erased.number, erased),
    by_name: dict.insert(service.by_name, erased.name, erased),
  )
}

pub fn set_keep_unrecognized_values(
  service: Service(meta, state, message),
  keep: Bool,
) -> Service(meta, state, message) {
  Service(..service, keep_unrecognized: keep)
}

pub fn set_can_send_unknown_error_message(
  service: Service(meta, state, message),
  can_send: fn(ServiceErrorInfo(meta, state)) -> Bool,
) -> Service(meta, state, message) {
  Service(..service, can_send_unknown_error_message: can_send)
}

pub fn set_error_logger(
  service: Service(meta, state, message),
  logger: fn(ServiceErrorInfo(meta, state)) -> Nil,
) -> Service(meta, state, message) {
  Service(..service, error_logger: logger)
}

pub fn set_studio_app_js_url(
  service: Service(meta, state, message),
  url: String,
) -> Service(meta, state, message) {
  Service(..service, studio_url: url)
}

// =============================================================================
// handle_request
// =============================================================================

pub fn handle_request(
  service: Service(meta, state, message),
  body: String,
  meta: meta,
  state: state,
) -> #(RawResponse, meta, message) {
  let trimmed = string.trim(body)
  case trimmed {
    "" | "studio" -> #(serve_studio(service), meta, service.empty_message)
    "list" -> #(serve_list(service), meta, service.empty_message)
    _ -> {
      case string.first(trimmed) {
        Ok("{") -> handle_json_request(service, trimmed, meta, state)
        _ -> handle_colon_request(service, trimmed, meta, state)
      }
    }
  }
}

// =============================================================================
// Private: request handling
// =============================================================================

fn handle_json_request(
  service: Service(meta, state, message),
  body: String,
  meta: meta,
  state: state,
) -> #(RawResponse, meta, message) {
  case parse_json_format(body) {
    Error(msg) -> #(
      RawResponse(status_code: 400, content_type: "text/plain", data: msg),
      meta,
      service.empty_message,
    )
    Ok(#(method_id, request_dynamic)) ->
      case lookup_method(service, method_id) {
        Error(_) -> #(
          RawResponse(
            status_code: 404,
            content_type: "text/plain",
            data: "method not found",
          ),
          meta,
          service.empty_message,
        )
        Ok(entry) ->
          invoke_entry(
            service,
            entry,
            request_dynamic,
            readable: True,
            meta: meta,
            state: state,
          )
      }
  }
}

fn handle_colon_request(
  service: Service(meta, state, message),
  body: String,
  meta: meta,
  state: state,
) -> #(RawResponse, meta, message) {
  case parse_colon_format(body) {
    Error(msg) -> #(
      RawResponse(status_code: 400, content_type: "text/plain", data: msg),
      meta,
      service.empty_message,
    )
    Ok(#(method_id, readable, request_dynamic)) ->
      case lookup_method(service, method_id) {
        Error(_) -> #(
          RawResponse(
            status_code: 404,
            content_type: "text/plain",
            data: "method not found",
          ),
          meta,
          service.empty_message,
        )
        Ok(entry) ->
          invoke_entry(
            service,
            entry,
            request_dynamic,
            readable: readable,
            meta: meta,
            state: state,
          )
      }
  }
}

fn lookup_method(
  service: Service(meta, state, message),
  method_id: MethodId,
) -> Result(ErasedMethod(meta, state, message), Nil) {
  case method_id {
    MethodIdName(name) -> dict.get(service.by_name, name)
    MethodIdNumber(n) -> dict.get(service.by_number, n)
  }
}

fn invoke_entry(
  service: Service(meta, state, message),
  entry: ErasedMethod(meta, state, message),
  request_dynamic: dynamic.Dynamic,
  readable readable: Bool,
  meta meta: meta,
  state state: state,
) -> #(RawResponse, meta, message) {
  let #(result, new_meta, new_state) =
    entry.invoke(
      request_dynamic,
      service.keep_unrecognized,
      readable,
      meta,
      state,
    )
  let raw = case result {
    Ok(response_json) ->
      RawResponse(
        status_code: 200,
        content_type: "application/json",
        data: response_json,
      )
    Error(ServiceError(status: status, message: msg)) ->
      RawResponse(
        status_code: error_status_to_http_code(status),
        content_type: "text/plain",
        data: msg,
      )
    Error(UnknownError(message: msg)) ->
      RawResponse(
        status_code: 500,
        content_type: "text/plain",
        data: case
          service.can_send_unknown_error_message(ErrorInfo(
            error: UnknownError(message: msg),
            message: msg,
            method_name: entry.name,
            request_meta: meta,
            state: state,
          ))
        {
          True -> "server error: " <> msg
          False -> "server error"
        },
      )
  }
  #(raw, new_meta, new_state)
}

// =============================================================================
// Private: list endpoint
// =============================================================================

fn serve_list(service: Service(meta, state, message)) -> RawResponse {
  let methods_json =
    service.by_name
    |> dict.values()
    |> list.map(fn(m) {
      let request_json =
        indent_multiline(m.request_type_descriptor_json, "      ")
      let response_json =
        indent_multiline(m.response_type_descriptor_json, "      ")
      "    {\n"
      <> "      \"method\": "
      <> json.to_string(json.string(m.name))
      <> ",\n      \"number\": "
      <> int.to_string(m.number)
      <> ",\n      \"doc\": "
      <> json.to_string(json.string(m.doc))
      <> ",\n      \"request\": "
      <> request_json
      <> ",\n      \"response\": "
      <> response_json
      <> "\n    }"
    })
    |> string.join(",\n")
  RawResponse(
    status_code: 200,
    content_type: "application/json",
    data: "{\n  \"methods\": [\n" <> methods_json <> "\n  ]\n}",
  )
}

fn indent_multiline(text: String, indent: String) -> String {
  case string.split(text, "\n") {
    [] -> text
    [first, ..rest] ->
      first
      <> case rest {
        [] -> ""
        _ ->
          "\n"
          <> rest
          |> list.map(fn(line) { indent <> line })
          |> string.join("\n")
      }
  }
}

// =============================================================================
// Private: studio endpoint
// =============================================================================

fn serve_studio(service: Service(meta, state, message)) -> RawResponse {
  let html =
    "<!DOCTYPE html>"
    <> "<html><head><meta charset=\"utf-8\"><title>Skir Studio</title>"
    <> "<link rel=\"icon\" href=\"data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🐙</text></svg>\">"
    <> "<script src=\""
    <> service.studio_url
    <> "\"></script>"
    <> "</head><body><skir-studio-app></skir-studio-app></body></html>"
  RawResponse(
    status_code: 200,
    content_type: "text/html; charset=utf-8",
    data: html,
  )
}

// =============================================================================
// Private: body parsers
// =============================================================================

type MethodId {
  MethodIdName(String)
  MethodIdNumber(Int)
}

fn parse_json_format(
  body: String,
) -> Result(#(MethodId, dynamic.Dynamic), String) {
  let decoder = {
    use method_dyn <- decode.field("method", decode.dynamic)
    use request_dyn <- decode.field("request", decode.dynamic)
    decode.success(#(method_dyn, request_dyn))
  }
  use #(method_dyn, request_dyn) <- result.try(
    json.parse(body, decoder)
    |> result.map_error(fn(_) { "invalid JSON body" }),
  )

  let method_id_result = case decode.run(method_dyn, decode.string) {
    Ok(s) -> Ok(MethodIdName(s))
    Error(_) ->
      case decode.run(method_dyn, decode.int) {
        Ok(n) -> Ok(MethodIdNumber(n))
        Error(_) -> Error("'method' field must be a string or integer")
      }
  }
  use mid <- result.try(method_id_result)

  Ok(#(mid, request_dyn))
}

fn parse_colon_format(
  body: String,
) -> Result(#(MethodId, Bool, dynamic.Dynamic), String) {
  case split_colon4(body) {
    Error(_) ->
      Error("invalid request format; expected name:number:format:requestJson")
    Ok(#(name, number_str, format, request_json)) -> {
      let method_id = case int.parse(number_str) {
        Ok(n) if n > 0 -> MethodIdNumber(n)
        _ -> MethodIdName(name)
      }
      let readable = format == "readable"
      case json.parse(from: request_json, using: decode.dynamic) {
        Ok(request_dynamic) -> Ok(#(method_id, readable, request_dynamic))
        Error(_) -> Error("invalid request JSON")
      }
    }
  }
}

fn split_colon4(s: String) -> Result(#(String, String, String, String), Nil) {
  case string.split_once(s, ":") {
    Error(_) -> Error(Nil)
    Ok(#(a, rest1)) ->
      case string.split_once(rest1, ":") {
        Error(_) -> Error(Nil)
        Ok(#(b, rest2)) ->
          case string.split_once(rest2, ":") {
            Error(_) -> Error(Nil)
            Ok(#(c, d)) -> Ok(#(a, b, c, d))
          }
      }
  }
}

fn error_status_to_http_code(status: HttpErrorCode) -> Int {
  case status {
    E400xBadRequest -> 400
    E401xUnauthorized -> 401
    E402xPaymentRequired -> 402
    E403xForbidden -> 403
    E404xNotFound -> 404
    E405xMethodNotAllowed -> 405
    E406xNotAcceptable -> 406
    E407xProxyAuthenticationRequired -> 407
    E408xRequestTimeout -> 408
    E409xConflict -> 409
    E410xGone -> 410
    E411xLengthRequired -> 411
    E412xPreconditionFailed -> 412
    E413xContentTooLarge -> 413
    E414xUriTooLong -> 414
    E415xUnsupportedMediaType -> 415
    E416xRangeNotSatisfiable -> 416
    E417xExpectationFailed -> 417
    E418xImATeapot -> 418
    E421xMisdirectedRequest -> 421
    E422xUnprocessableContent -> 422
    E423xLocked -> 423
    E424xFailedDependency -> 424
    E425xTooEarly -> 425
    E426xUpgradeRequired -> 426
    E428xPreconditionRequired -> 428
    E429xTooManyRequests -> 429
    E431xRequestHeaderFieldsTooLarge -> 431
    E451xUnavailableForLegalReasons -> 451
    E500xInternalServerError -> 500
    E501xNotImplemented -> 501
    E502xBadGateway -> 502
    E503xServiceUnavailable -> 503
    E504xGatewayTimeout -> 504
    E505xHttpVersionNotSupported -> 505
    E506xVariantAlsoNegotiates -> 506
    E507xInsufficientStorage -> 507
    E508xLoopDetected -> 508
    E510xNotExtended -> 510
    E511xNetworkAuthenticationRequired -> 511
  }
}

// =============================================================================
// Private: default error logger (no-op)
// =============================================================================

fn noop_error_logger(_info: ServiceErrorInfo(meta, state)) -> Nil {
  Nil
}

// Studio JS CDN URL — override with set_studio_app_js_url if needed.
const default_studio_url = "https://cdn.jsdelivr.net/npm/skir-studio/dist/skir-studio-standalone.js"
