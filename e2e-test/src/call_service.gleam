// TEMPORARY script to demo calling a SkirRPC service with gleam_httpc.
// TO REMOVE:
//   1. Delete this file (src/call_service.gleam).
//   2. Remove mist, gleam_httpc, gleam_erlang from [dependencies] in gleam.toml.

import gleam/httpc
import gleam/int
import gleam/io
import skir_client/service_client
import skirout/user.{User, UserProfile} as user_out

pub fn main() {
  // Create a service client that uses gleam_httpc as the transport.
  let assert Ok(client) =
    service_client.new("http://localhost:8787", httpc.send)

  // --- Add a user ---
  let new_profile =
    UserProfile(
      ..user_out.user_profile_default,
      user: User(..user_out.user_default, user_id: 42),
    )
  case
    service_client.invoke_remote(
      client,
      user_out.add_user_method(),
      new_profile,
      [],
    )
  {
    Error(e) ->
      io.println(
        "add_user failed: " <> int.to_string(e.status_code) <> " " <> e.message,
      )
    Ok(user) ->
      io.println("add_user returned user_id=" <> int.to_string(user.user_id))
  }

  // --- Get user #1 ---
  let req = User(..user_out.user_default, user_id: 1)
  case
    service_client.invoke_remote(client, user_out.get_user_method(), req, [])
  {
    Error(e) ->
      io.println(
        "get_user failed: " <> int.to_string(e.status_code) <> " " <> e.message,
      )
    Ok(profile) ->
      io.println(
        "get_user returned profile for user_id="
        <> int.to_string(profile.user.user_id),
      )
  }
}
