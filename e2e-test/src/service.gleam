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
import serializer.{type UnrecognizedValues, Drop, Keep}
import type_descriptor

// Studio JS CDN URL — override with set_studio_app_js_url if needed.
const default_studio_url = "https://cdn.jsdelivr.net/npm/skir-studio/dist/skir-studio-standalone.js"

// =============================================================================
// ServiceError
// =============================================================================

/// A controlled error that is sent back to the caller as a non-2xx HTTP
/// response.  Use this in your method implementations to signal expected
/// failures (e.g. "not found", "permission denied").
pub type ServiceError {
  ServiceError(status_code: Int, message: String)
}

// =============================================================================
// RawResponse
// =============================================================================

/// The return value of handle_request.
pub type RawResponse {
  RawResponse(status_code: Int, content_type: String, data: String)
}

// =============================================================================
// Internal: type-erased method
// =============================================================================

type InvokeFn(meta) =
  fn(dynamic.Dynamic, Bool, Bool, meta) -> #(Result(String, ServiceError), meta)

type ErasedMethod(meta) {
  ErasedMethod(
    name: String,
    number: Int,
    doc: String,
    request_type_descriptor_json: String,
    response_type_descriptor_json: String,
    invoke: InvokeFn(meta),
  )
}

fn make_erased_method(
  method: Method(req, resp),
  handler: fn(req, meta) -> #(Result(resp, ServiceError), meta),
) -> ErasedMethod(meta) {
  let request_td_json =
    method.request_serializer
    |> serializer.type_descriptor()
    |> type_descriptor.type_descriptor_to_json()
  let response_td_json =
    method.response_serializer
    |> serializer.type_descriptor()
    |> type_descriptor.type_descriptor_to_json()

  let invoke = fn(request_dynamic, keep_bool, readable, meta) {
    let keep: UnrecognizedValues = case keep_bool {
      True -> Keep
      False -> Drop
    }
    case
      decode.run(
        request_dynamic,
        serializer.json_decoder_with_options(
          method.request_serializer,
          keep_unrecognized_values: keep,
        ),
      )
    {
      Error(errors) -> #(
        Error(ServiceError(
          status_code: 400,
          message: "bad request: " <> json_utils.decode_errors_to_string(errors),
        )),
        meta,
      )
      Ok(req) ->
        case handler(req, meta) {
          #(Error(e), new_meta) -> #(Error(e), new_meta)
          #(Ok(response_value), new_meta) -> {
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
            #(Ok(json_str), new_meta)
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

pub opaque type Service(meta) {
  Service(
    keep_unrecognized: Bool,
    can_send_unknown_error_message: Bool,
    error_logger: fn(String) -> Nil,
    studio_url: String,
    by_number: Dict(Int, ErasedMethod(meta)),
    by_name: Dict(String, ErasedMethod(meta)),
  )
}

// =============================================================================
// ServiceBuilder
// =============================================================================

pub opaque type ServiceBuilder(meta) {
  ServiceBuilder(
    keep_unrecognized: Bool,
    can_send_unknown_error_message: Bool,
    error_logger: fn(String) -> Nil,
    studio_url: String,
    methods: List(ErasedMethod(meta)),
  )
}

pub fn builder() -> ServiceBuilder(meta) {
  ServiceBuilder(
    keep_unrecognized: False,
    can_send_unknown_error_message: False,
    error_logger: log_to_stderr,
    studio_url: default_studio_url,
    methods: [],
  )
}

pub fn add_method(
  builder: ServiceBuilder(meta),
  method: Method(req, resp),
  handler: fn(req, meta) -> #(Result(resp, ServiceError), meta),
) -> ServiceBuilder(meta) {
  ServiceBuilder(
    ..builder,
    methods: list.append(builder.methods, [make_erased_method(method, handler)]),
  )
}

pub fn set_keep_unrecognized_values(
  builder: ServiceBuilder(meta),
  keep: Bool,
) -> ServiceBuilder(meta) {
  ServiceBuilder(..builder, keep_unrecognized: keep)
}

pub fn set_can_send_unknown_error_message(
  builder: ServiceBuilder(meta),
  can_send: Bool,
) -> ServiceBuilder(meta) {
  ServiceBuilder(..builder, can_send_unknown_error_message: can_send)
}

pub fn set_error_logger(
  builder: ServiceBuilder(meta),
  logger: fn(String) -> Nil,
) -> ServiceBuilder(meta) {
  ServiceBuilder(..builder, error_logger: logger)
}

pub fn set_studio_app_js_url(
  builder: ServiceBuilder(meta),
  url: String,
) -> ServiceBuilder(meta) {
  ServiceBuilder(..builder, studio_url: url)
}

pub fn build(builder: ServiceBuilder(meta)) -> Service(meta) {
  let by_number =
    list.fold(builder.methods, dict.new(), fn(acc, m) {
      dict.insert(acc, m.number, m)
    })
  let by_name =
    list.fold(builder.methods, dict.new(), fn(acc, m) {
      dict.insert(acc, m.name, m)
    })
  Service(
    keep_unrecognized: builder.keep_unrecognized,
    can_send_unknown_error_message: builder.can_send_unknown_error_message,
    error_logger: builder.error_logger,
    studio_url: builder.studio_url,
    by_number: by_number,
    by_name: by_name,
  )
}

// =============================================================================
// handle_request
// =============================================================================

pub fn handle_request(
  service: Service(meta),
  body: String,
  meta: meta,
) -> #(RawResponse, meta) {
  let trimmed = string.trim(body)
  case trimmed {
    "" | "studio" -> #(serve_studio(service), meta)
    "list" -> #(serve_list(service), meta)
    _ -> {
      case string.first(trimmed) {
        Ok("{") -> handle_json_request(service, trimmed, meta)
        _ -> handle_colon_request(service, trimmed, meta)
      }
    }
  }
}

// =============================================================================
// Private: request handling
// =============================================================================

fn handle_json_request(
  service: Service(meta),
  body: String,
  meta: meta,
) -> #(RawResponse, meta) {
  case parse_json_format(body) {
    Error(msg) -> #(
      RawResponse(status_code: 400, content_type: "text/plain", data: msg),
      meta,
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
        )
        Ok(entry) ->
          invoke_entry(
            service,
            entry,
            request_dynamic,
            readable: True,
            meta: meta,
          )
      }
  }
}

fn handle_colon_request(
  service: Service(meta),
  body: String,
  meta: meta,
) -> #(RawResponse, meta) {
  case parse_colon_format(body) {
    Error(msg) -> #(
      RawResponse(status_code: 400, content_type: "text/plain", data: msg),
      meta,
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
        )
        Ok(entry) ->
          invoke_entry(
            service,
            entry,
            request_dynamic,
            readable: readable,
            meta: meta,
          )
      }
  }
}

fn lookup_method(
  service: Service(meta),
  method_id: MethodId,
) -> Result(ErasedMethod(meta), Nil) {
  case method_id {
    MethodIdName(name) -> dict.get(service.by_name, name)
    MethodIdNumber(n) -> dict.get(service.by_number, n)
  }
}

fn invoke_entry(
  service: Service(meta),
  entry: ErasedMethod(meta),
  request_dynamic: dynamic.Dynamic,
  readable readable: Bool,
  meta meta: meta,
) -> #(RawResponse, meta) {
  let #(result, new_meta) =
    entry.invoke(request_dynamic, service.keep_unrecognized, readable, meta)
  let raw = case result {
    Ok(response_json) ->
      RawResponse(
        status_code: 200,
        content_type: "application/json",
        data: response_json,
      )
    Error(ServiceError(status_code: code, message: msg)) ->
      RawResponse(status_code: code, content_type: "text/plain", data: msg)
  }
  #(raw, new_meta)
}

// =============================================================================
// Private: list endpoint
// =============================================================================

fn serve_list(service: Service(meta)) -> RawResponse {
  let methods_json =
    service.by_name
    |> dict.values()
    |> list.map(fn(m) {
      "  {\n"
      <> "    \"method\": "
      <> json.to_string(json.string(m.name))
      <> ",\n    \"number\": "
      <> int.to_string(m.number)
      <> ",\n    \"doc\": "
      <> json.to_string(json.string(m.doc))
      <> ",\n    \"request\": "
      <> m.request_type_descriptor_json
      <> ",\n    \"response\": "
      <> m.response_type_descriptor_json
      <> "\n  }"
    })
    |> string.join(",\n")
  RawResponse(
    status_code: 200,
    content_type: "application/json",
    data: "{\n  \"methods\": [\n" <> methods_json <> "\n  ]\n}",
  )
}

// =============================================================================
// Private: studio endpoint
// =============================================================================

fn serve_studio(service: Service(meta)) -> RawResponse {
  let html =
    "<!DOCTYPE html>"
    <> "<html><head><meta charset=\"utf-8\"><title>Skir Studio</title>"
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

// =============================================================================
// Private: default error logger (no-op)
// =============================================================================

// The default logger does nothing; callers should override it via
// set_error_logger if they want error reporting.
fn log_to_stderr(_message: String) -> Nil {
  Nil
}
