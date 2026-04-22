// TEMPORARY script to demo running a SkirRPC service with mist.
// TO REMOVE:
//   1. Delete this file (src/start_service.gleam).
//   2. Remove mist, gleam_httpc, gleam_erlang from [dependencies] in gleam.toml.

import gleam/bit_array
import gleam/bytes_tree
import gleam/dict
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/option
import mist
import service.{type RawResponse, type Service, type ServiceError, ServiceError}
import skirout/user.{type User, type UserProfile, User, UserProfile} as user_out

// ---------------------------------------------------------------------------
// In-memory user store
// ---------------------------------------------------------------------------

type State =
  dict.Dict(Int, UserProfile)

type StateMessage {
  HandleRpc(process.Subject(RawResponse), String)
}

// ---------------------------------------------------------------------------
// Method implementations
// ---------------------------------------------------------------------------

fn get_user(
  req: User,
  state: State,
) -> #(Result(UserProfile, ServiceError), State) {
  case dict.get(state, req.user_id) {
    Ok(profile) -> #(Ok(profile), state)
    Error(_) -> #(
      Error(ServiceError(
        status_code: 404,
        message: "user not found: " <> int.to_string(req.user_id),
      )),
      state,
    )
  }
}

fn add_user(
  req: UserProfile,
  state: State,
) -> #(Result(User, ServiceError), State) {
  let new_state = dict.insert(state, req.user.user_id, req)
  #(Ok(req.user), new_state)
}

// ---------------------------------------------------------------------------
// Service definition
// ---------------------------------------------------------------------------

fn build_service() -> Service(State) {
  service.builder()
  |> service.add_method(user_out.get_user_method(), get_user)
  |> service.add_method(user_out.add_user_method(), add_user)
  |> service.set_keep_unrecognized_values(True)
  |> service.set_can_send_unknown_error_message(True)
  |> service.set_error_logger(fn(msg) { io.println_error(msg) })
  |> service.build()
}

fn state_loop(
  subject: process.Subject(StateMessage),
  svc: Service(State),
  state: State,
) -> Nil {
  case process.receive_forever(subject) {
    HandleRpc(reply, input) -> {
      let #(raw, new_state) = service.handle_request(svc, input, state)
      process.send(reply, raw)
      state_loop(subject, svc, new_state)
    }
  }
}

// ---------------------------------------------------------------------------
// HTTP handler
// ---------------------------------------------------------------------------

fn handle_request(
  req: request.Request(mist.Connection),
  state_subject: process.Subject(StateMessage),
) -> response.Response(mist.ResponseData) {
  // Read the body (max 4 MB).
  let body_str = case mist.read_body(req, 4 * 1024 * 1024) {
    Error(_) -> ""
    Ok(req_with_body) ->
      case bit_array.to_string(req_with_body.body) {
        Ok(s) -> s
        Error(_) -> ""
      }
  }

  // For GET requests (or any request with an empty body), fall back to the
  // query string so that e.g. GET /?list or GET /?GetUser:{...} works.
  let input = case body_str {
    "" -> option.unwrap(req.query, "")
    _ -> body_str
  }

  // Dispatch through the SkirRPC service and persist state in the state loop.
  let raw = process.call_forever(state_subject, HandleRpc(_, input))

  response.new(raw.status_code)
  |> response.set_header("content-type", raw.content_type)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(raw.data)))
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

pub fn main() {
  // A simple in-memory store with a couple of pre-populated users.
  let state: State =
    dict.from_list([
      #(
        1,
        UserProfile(
          ..user_out.user_profile_default,
          user: User(..user_out.user_default, user_id: 1),
        ),
      ),
      #(
        2,
        UserProfile(
          ..user_out.user_profile_default,
          user: User(..user_out.user_default, user_id: 2),
        ),
      ),
    ])

  let svc = build_service()

  let startup_subject = process.new_subject()
  let _state_pid =
    process.spawn(fn() {
      let state_subject = process.new_subject()
      process.send(startup_subject, state_subject)
      state_loop(state_subject, svc, state)
    })
  let state_subject = process.receive_forever(startup_subject)

  let handler = fn(req) { handle_request(req, state_subject) }

  let assert Ok(_) =
    handler
    |> mist.new()
    |> mist.port(8787)
    |> mist.start()

  io.println("SkirRPC service listening on http://localhost:8787")
  io.println("Try: echo 'list' | curl -s -X POST http://localhost:8787 -d @-")

  process.sleep_forever()
}
