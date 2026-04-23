import gleam/http
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleam/uri
import internal/method.{type Method}
import internal/type_adapter.{Keep}
import serializer

// =============================================================================
// RpcError
// =============================================================================

/// Error returned by invoke_remote when the server responds with a non-2xx
/// status code or when a network-level failure occurs.
pub type RpcError {
  RpcError(
    /// HTTP status code from the server, or 0 for network-level failures.
    status_code: Int,
    /// Human-readable description of the error.
    message: String,
  )
}

// =============================================================================
// ServiceClient
// =============================================================================

/// Sends RPCs to a SkirRPC service.
///
/// The send_fn parameter accepts an HTTP request and returns a response.
/// Its signature matches httpc.send from the gleam_httpc package, so you can
/// pass httpc.send directly (or any compatible function).
///
/// Example:
///   import gleam/httpc
///   import skir_client/service_client
///   let assert Ok(client) =
///     service_client.new("http://localhost:8787/myapi", httpc.send)
pub opaque type ServiceClient(send_err) {
  ServiceClient(
    service_url: String,
    parsed_url: uri.Uri,
    default_headers: List(#(String, String)),
    send_fn: fn(request.Request(String)) -> Result(Response(String), send_err),
  )
}

/// Creates a ServiceClient pointing at service_url.
///
/// send_fn is the HTTP send function. Pass httpc.send from gleam_httpc or
/// any function with the same signature.
///
/// Returns an error string if service_url contains a query string or is not
/// a valid URL.
pub fn new(
  service_url: String,
  send_fn: fn(request.Request(String)) -> Result(Response(String), send_err),
) -> Result(ServiceClient(send_err), String) {
  case string.contains(service_url, "?") {
    True -> Error("service URL must not contain a query string")
    False ->
      case uri.parse(service_url) {
        Error(_) -> Error("service URL is not a valid URL: " <> service_url)
        Ok(parsed) ->
          Ok(ServiceClient(
            service_url: service_url,
            parsed_url: parsed,
            default_headers: [],
            send_fn: send_fn,
          ))
      }
  }
}

/// Adds a default HTTP header sent with every invocation.
///
/// May be chained: client |> with_default_header("Authorization", "Bearer ...")
pub fn with_default_header(
  client: ServiceClient(send_err),
  key: String,
  value: String,
) -> ServiceClient(send_err) {
  ServiceClient(
    ..client,
    default_headers: list.append(client.default_headers, [#(key, value)]),
  )
}

/// Invokes method on the remote service with the given request_value.
///
/// extra_headers is a list of #(name, value) pairs that supplement (or
/// override) the default headers for this specific call only.
///
/// The request is serialized as dense JSON.  The response is deserialized
/// keeping any unrecognized values (the server may have a newer schema).
pub fn invoke_remote(
  client: ServiceClient(send_err),
  method: Method(req, resp),
  request_value: req,
  extra_headers: List(#(String, String)),
) -> Result(resp, RpcError) {
  // Serialize the request as dense JSON.
  let request_json =
    serializer.to_dense_json_code(method.request_serializer, request_value)

  // Wire body: "MethodName:number::requestJson"
  // The empty third field signals that the server may reply in dense JSON.
  let wire_body =
    method.name <> ":" <> int.to_string(method.number) <> "::" <> request_json

  // Build the HTTP request from the pre-parsed URL.
  let p = client.parsed_url
  let scheme = case p.scheme {
    option.Some("https") -> http.Https
    _ -> http.Http
  }
  let host = option.unwrap(p.host, "localhost")
  let path = case p.path {
    "" -> "/"
    s -> s
  }
  let req = request.new()
  let req = request.Request(..req, scheme: scheme, host: host, path: path)
  let req = case p.port {
    option.Some(port) -> request.set_port(req, port)
    option.None -> req
  }
  let req =
    req
    |> request.set_method(http.Post)
    |> request.set_body(wire_body)
    |> request.prepend_header("content-type", "text/plain; charset=utf-8")

  // Apply default headers, then per-call extra headers.
  let req =
    list.fold(client.default_headers, req, fn(r, pair) {
      request.set_header(r, pair.0, pair.1)
    })
  let req =
    list.fold(extra_headers, req, fn(r, pair) {
      request.set_header(r, pair.0, pair.1)
    })

  // Send the request.
  case client.send_fn(req) {
    Error(_) ->
      Error(RpcError(status_code: 0, message: "network error: request failed"))
    Ok(resp) ->
      case resp.status >= 200 && resp.status < 300 {
        False -> {
          let message = case
            response.get_header(resp, "content-type")
            |> result.map(string.contains(_, "text/plain"))
          {
            Ok(True) -> resp.body
            _ -> ""
          }
          Error(RpcError(status_code: resp.status, message: message))
        }
        True ->
          serializer.from_json_code_with_options(
            method.response_serializer,
            resp.body,
            keep_unrecognized_values: Keep,
          )
          |> result.map_error(fn(e) {
            RpcError(
              status_code: 0,
              message: "failed to decode response: " <> e,
            )
          })
      }
  }
}
