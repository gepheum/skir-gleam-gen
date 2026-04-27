[![npm](https://img.shields.io/npm/v/skir-gleam-gen)](https://www.npmjs.com/package/skir-gleam-gen)
[![build](https://github.com/gepheum/skir-gleam-gen/workflows/Build/badge.svg)](https://github.com/gepheum/skir-gleam-gen/actions)

# Skir's Gleam code generator

Official plugin for generating Gleam code from [.skir](https://github.com/gepheum/skir) files.

## Set up

In your `skir.yml` file, add the following snippet under `generators`:
```yaml
  - mod: skir-gleam-gen
    outDir: ./src/skirout
    config: {}
```

The generated Gleam code has a runtime dependency on `skir_client`. Add it to your project with:

```shell
gleam add skir_client
```

For more information, see this Gleam project [example](https://github.com/gepheum/skir-gleam-example).

## Gleam generated code guide

The examples below are for the code generated from [this](https://github.com/gepheum/skir-gleam-example/blob/main/skir-src/user.skir) .skir file.

### Referring to generated symbols

```gleam
// Import the module generated from "user.skir"
import skirout/user

// Now you can use: user.User, user.SubscriptionStatus, user.tarzan_const, etc.
```

### Struct types

Skir generates a plain Gleam record for every struct in the .skir file.

```gleam
import skir_client
import skir_client/timestamp
import skirout/user

// Construct a User using the generated helper function.
// The helper sets the `unrecognized_` field automatically.
let john =
  user.user_new(
    "John Doe",
    [
      user.user__pet_new(1.0, "Dumbo", "🐘"),
    ],
    "Coffee is just a socially acceptable form of rage.",
    user.SubscriptionStatusFree,
    42,
  )

io.println(john.name)
// John Doe

// `user_default` holds a User with every field set to its default value.
io.println(user.user_default.name)
// (empty string)
io.println(int.to_string(user.user_default.user_id))
// 0

// Gleam's record update syntax lets you specify just a few fields and keep
// the rest from an existing instance.
let jane = user.User(..user.user_default, user_id: 43, name: "Jane Doe")

io.println(jane.quote)
// (empty string)
io.println(int.to_string(list.length(jane.pets)))
// 0
```

#### Creating modified copies

```gleam
// Gleam records are immutable. Use record update syntax to create a modified
// copy without changing the original.
let evil_john =
  user.User(
    ..john,
    name: "Evil John",
    quote: "I solemnly swear I am up to no good.",
  )

io.println(evil_john.name)
// Evil John
io.println(int.to_string(evil_john.user_id))
// 42 (copied from john)
io.println(john.name)
// John Doe (john is unchanged)
```

### Enum types

The definition of the `SubscriptionStatus` enum in the .skir file is:
```rust
enum SubscriptionStatus {
  FREE;
  trial: Trial;
  PREMIUM;
}
```

Skir generates a Gleam custom type for every enum in the .skir file.

#### Constructing enum values

```gleam
let _statuses = [
  // Unknown is the default and is present in all Skir enums even if it is not
  // declared in the .skir file.
  user.subscription_status_unknown,
  user.SubscriptionStatusFree,
  user.SubscriptionStatusPremium,
  // Wrapper variants carry an inner struct.
  user.SubscriptionStatusTrialX(
    user.subscription_status__trial_new(
      timestamp.Timestamp(unix_millis: 1_743_592_409_000),
    ),
  ),
]
```

#### Pattern matching on enums

```gleam
let get_info_text = fn(status: user.SubscriptionStatus) -> String {
  case status {
    user.SubscriptionStatusFree -> "Free user"
    user.SubscriptionStatusPremium -> "Premium user"
    user.SubscriptionStatusTrialX(t) ->
      "On trial since " <> int.to_string(t.start_time.unix_millis)
    user.SubscriptionStatusUnknown(_) -> "Unknown subscription status"
  }
}

io.println(get_info_text(john.subscription_status))
// Free user

let trial_status =
  user.SubscriptionStatusTrialX(
    user.subscription_status__trial_new(
      timestamp.Timestamp(unix_millis: 1_743_592_409_000),
    ),
  )
io.println(get_info_text(trial_status))
// On trial since 1743592409000
```

### Serialization

The serializer for a type is returned by calling the generated `*_serializer()` function. Use functions from `skir_client` to serialize and deserialize values.

```gleam
let serializer = user.user_serializer()

// Serialize 'john' to dense JSON (field-number-based; the default mode).
// Use this when you plan to deserialize the value later. Because field
// names are not included, renaming a field remains backward-compatible.
let john_dense_json = skir_client.to_dense_json_code(serializer, john)
io.println(john_dense_json)
// [42,"John Doe",...]

// Serialize 'john' to readable (name-based, indented) JSON.
// Use this mainly for debugging.
io.println(skir_client.to_readable_json_code(serializer, john))
// {
//   "user_id": 42,
//   "name": "John Doe",
//   "quote": "Coffee is just a socially acceptable form of rage.",
//   "pets": [
//     {
//       "name": "Dumbo",
//       "height_in_meters": 1.0,
//       "picture": "🐘"
//     }
//   ],
//   "subscription_status": "FREE"
// }

// The dense JSON flavor is the flavor you should pick if you intend to
// deserialize the value in the future. Skir allows fields to be renamed,
// and because field names are not part of the dense JSON, renaming a field
// does not prevent you from deserializing the value.
// You should pick the readable flavor mostly for debugging purposes.

// Serialize 'john' to binary format.
let john_bytes = skir_client.to_bytes(serializer, john)

// The binary format is not human readable, but it is slightly more compact
// than JSON, and serialization/deserialization can be a bit faster in
// languages like C++. Only use it when this small performance gain is
// likely to matter, which should be rare.
```

### Deserialization

```gleam
// Use from_json_code() and from_bytes() to deserialize.
// Both accept dense and readable JSON.

let assert Ok(reserialized_john) =
  skir_client.from_json_code(serializer, john_dense_json)
let assert True = reserialized_john == john

let assert Ok(from_bytes) = skir_client.from_bytes(serializer, john_bytes)
let assert True = from_bytes == john
```

### Primitive serializers

```gleam
io.println(skir_client.to_dense_json_code(skir_client.bool_serializer(), True))
// 1
io.println(skir_client.to_dense_json_code(skir_client.int32_serializer(), 3))
// 3
io.println(skir_client.to_dense_json_code(
  skir_client.int64_serializer(),
  9_223_372_036_854_775_807,
))
// "9223372036854775807"
io.println(skir_client.to_dense_json_code(
  skir_client.timestamp_serializer(),
  timestamp.Timestamp(unix_millis: 1_743_682_787_000),
))
// 1743682787000
io.println(skir_client.to_dense_json_code(skir_client.float32_serializer(), 1.5))
// 1.5
io.println(skir_client.to_dense_json_code(skir_client.float64_serializer(), 1.5))
// 1.5
io.println(skir_client.to_dense_json_code(skir_client.string_serializer(), "Foo"))
// "Foo"
```

### Composite serializers

```gleam
// Optional serializer:
io.println(skir_client.to_dense_json_code(
  skir_client.optional_serializer(skir_client.string_serializer()),
  option.Some("foo"),
))
// "foo"

io.println(skir_client.to_dense_json_code(
  skir_client.optional_serializer(skir_client.string_serializer()),
  option.None,
))
// null

// List serializer:
io.println(skir_client.to_dense_json_code(
  skir_client.list_serializer(skir_client.bool_serializer()),
  [True, False],
))
// [1,0]
```

### Constants

```gleam
// Constants declared with 'const' in the .skir file are available as
// top-level constants in the generated Gleam code.
io.println(skir_client.to_readable_json_code(
  user.user_serializer(),
  user.tarzan_const,
))
// {
//   "user_id": 123,
//   "name": "Tarzan",
//   "quote": "AAAAaAaAaAyAAAAaAaAaAyAAAAaAaAaA",
//   "pets": [
//     {
//       "name": "Cheeta",
//       "height_in_meters": 1.67,
//       "picture": "🐒"
//     }
//   ],
//   "subscription_status": {
//     "kind": "trial",
//     "value": {
//       "start_time": {
//         "unix_millis": 1743592409000,
//         "formatted": "2025-04-02T11:13:29Z"
//       }
//     }
//   }
// }
```

### SkirRPC services

#### Starting a SkirRPC service on an HTTP server

Full example [here](https://github.com/gepheum/skir-gleam-example/blob/main/src/start_service.gleam).

#### Sending RPCs to a SkirRPC service

Full example [here](https://github.com/gepheum/skir-gleam-example/blob/main/src/call_service.gleam).

### Reflection

Reflection allows you to inspect a Skir type at runtime.

```gleam
import gleam/dict
import gleam/list
import skir_client
import skir_client/type_descriptor

let user_type_descriptor = skir_client.type_descriptor(user.user_serializer())

// Print the full type descriptor as JSON.
io.println(type_descriptor.type_descriptor_to_json(user_type_descriptor))
// {
//   "type": {
//     "kind": "record",
//     "value": "user.skir:User"
//   },
//   "records": [
//     {
//       "kind": "struct",
//       "id": "user.skir:User",
//       "fields": [
//         {
//           "name": "user_id",
//           "number": 0,
//           "type": { "kind": "primitive", "value": "int32" }
//         },
//         ...
//       ]
//     },
//     ...
//   ]
// }

// Pattern match on the records map to inspect the User struct's fields.
let assert Ok(type_descriptor.StructRecord(user_struct)) =
  dict.get(user_type_descriptor.records, "user.skir:User")

let field_names = list.map(user_struct.fields, fn(f) { f.name })
io.println(string.join(field_names, ", "))
// user_id, name, quote, pets, subscription_status

io.println(int.to_string(list.length(user_struct.fields)))
// 5

// A TypeDescriptor can be serialized to JSON and parsed back.
let type_descriptor_json =
  type_descriptor.type_descriptor_to_json(user_type_descriptor)
let assert Ok(reparsed_type_descriptor) =
  type_descriptor.type_descriptor_from_json(type_descriptor_json)
let assert True = reparsed_type_descriptor == user_type_descriptor
```
