# Building a Custom Advantage Service

Some platforms expose proprietary APIs alongside standard LTI services.
You can plug these into Ltix's OAuth flow by implementing the
`Ltix.AdvantageService` behaviour, giving your custom service the same
authentication and token management as built-in services like
`Ltix.GradeService` and `Ltix.MembershipsService`.

This cookbook walks through building a client for a fictional Attendance
service. The platform tracks class attendance and exposes a read-only
API to query attendance records for a course.

## Endpoint struct

Start with a struct representing the endpoint claim the platform sends
in the launch JWT. The Attendance service has one URL and one scope:

```elixir
# lib/my_app/lti/attendance_endpoint.ex
defmodule MyApp.Lti.AttendanceEndpoint do
  defstruct [:attendance_url]

  @claim_key "https://lms.example.com/claim/attendance"

  def claim_key, do: @claim_key

  def parse(%{"attendance_url" => url}) when is_binary(url) do
    {:ok, %__MODULE__{attendance_url: url}}
  end

  def parse(_), do: {:error, "invalid attendance claim"}
end
```

The `parse/1` function follows the claim parser contract: receive the
raw claim value, return `{:ok, parsed}` or `{:error, reason}`. See
[Custom Claim Parsers](../custom-claim-parsers.md) for the full guide.

## Register the claim parser

Register the parser so the endpoint struct is available in
`context.claims.extensions` after launch:

```elixir
# config/config.exs
config :ltix, Ltix.LaunchClaims,
  claim_parsers: %{
    "https://lms.example.com/claim/attendance" =>
      &MyApp.Lti.AttendanceEndpoint.parse/1
  }
```

After a launch, the parsed endpoint is at:

```elixir
context.claims.extensions["https://lms.example.com/claim/attendance"]
#=> %MyApp.Lti.AttendanceEndpoint{attendance_url: "https://lms.example.com/api/attendance/ctx-123"}
```

## Service module

Implement the `Ltix.AdvantageService` behaviour. The three callbacks
tell `Ltix.OAuth` how to validate your endpoint and which scopes to
request:

```elixir
# lib/my_app/lti/attendance_service.ex
defmodule MyApp.Lti.AttendanceService do
  @behaviour Ltix.AdvantageService

  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias MyApp.Lti.AttendanceEndpoint

  @scope "https://lms.example.com/scope/attendance.readonly"
  @claim_key AttendanceEndpoint.claim_key()

  # Custom claims live in extensions, not a named struct field.
  @impl true
  def endpoint_from_claims(%Ltix.LaunchClaims{extensions: extensions}) do
    case Map.fetch(extensions, @claim_key) do
      {:ok, %AttendanceEndpoint{} = ep} -> {:ok, ep}
      _ -> :error
    end
  end

  @impl true
  def validate_endpoint(%AttendanceEndpoint{}), do: :ok
  def validate_endpoint(_), do: {:error, InvalidEndpoint.exception(service: __MODULE__)}

  @impl true
  def scopes(%AttendanceEndpoint{}), do: [@scope]
end
```

`endpoint_from_claims/1` reads from `extensions` because custom claims
don't get a named field on `Ltix.LaunchClaims`. This is the only
structural difference from a built-in service.

## Authenticating

With the behaviour in place, authenticate through `Ltix.OAuth`.

**From a launch context:**

```elixir
alias MyApp.Lti.{AttendanceEndpoint, AttendanceService}

def handle_launch(context) do
  claim_key = AttendanceEndpoint.claim_key()
  endpoint = context.claims.extensions[claim_key]

  {:ok, client} = Ltix.OAuth.authenticate(context.registration,
    endpoints: %{AttendanceService => endpoint}
  )

  {:ok, records} = AttendanceService.get_records(client)
end
```

**From a stored endpoint** (background job, no launch context):

```elixir
endpoint = %AttendanceEndpoint{attendance_url: stored_url}

{:ok, client} = Ltix.OAuth.authenticate(registration,
  endpoints: %{AttendanceService => endpoint}
)
```

Both paths produce the same `%Ltix.OAuth.Client{}`. The client carries
your endpoint in its `endpoints` map, keyed by `AttendanceService`.

## Making authenticated requests

The client gives you a bearer token and Req options. Build your
request as a keyword list and pass it to Req:

```elixir
# lib/my_app/lti/attendance_service.ex

alias Ltix.OAuth.Client

@spec get_records(Client.t()) :: {:ok, [map()]} | {:error, Exception.t()}
def get_records(%Client{} = client) do
  endpoint = client.endpoints[__MODULE__]

  req_opts =
    client.req_options
    |> Keyword.put(:url, endpoint.attendance_url)
    |> Keyword.put(:headers, [
      {"authorization", "Bearer #{client.access_token}"},
      {"accept", "application/json"}
    ])

  case Req.get(req_opts) do
    {:ok, %Req.Response{status: 200, body: body}} ->
      {:ok, body["records"]}

    {:ok, %Req.Response{status: status}} ->
      {:error, RuntimeError.exception("attendance request failed: HTTP #{status}")}

    {:error, exception} ->
      {:error, exception}
  end
end
```

`client.req_options` carries the Req options that were passed to
`Ltix.OAuth.authenticate/2`. Set `:url` and `:headers` on top of
them with `Keyword.put/3`. The bearer token comes from
`client.access_token`, and the endpoint URL from
`client.endpoints[__MODULE__]`.

## Adding an expiry check

Tokens expire after about an hour. For request handlers that
authenticate and immediately call the service, this isn't a concern.
For longer-lived processes, check before each call:

```elixir
def get_records(%Client{} = client) do
  if Client.expired?(client) do
    {:error, Ltix.Errors.Security.AccessTokenExpired.exception([])}
  else
    do_get_records(client)
  end
end
```

Or refresh automatically:

```elixir
client = Client.refresh!(client)
```

See [Token Caching and Reuse](token-caching-and-reuse.md) for patterns
around batch refreshing and ETS caching.

## Testing

Test your service the same way Ltix tests its built-in services: stub
the token endpoint and your service's HTTP calls with `Req.Test`.

```elixir
# test/my_app/lti/attendance_service_test.exs
defmodule MyApp.Lti.AttendanceServiceTest do
  use ExUnit.Case, async: true

  alias Ltix.OAuth.Client
  alias MyApp.Lti.{AttendanceEndpoint, AttendanceService}

  @attendance_url "https://lms.example.com/api/attendance/ctx-123"
  @scope "https://lms.example.com/scope/attendance.readonly"

  setup do
    platform = Ltix.Test.setup_platform!()
    %{platform: platform}
  end

  defp build_client(platform) do
    %Client{
      access_token: "test-attendance-token",
      expires_at: DateTime.add(DateTime.utc_now(), 3600),
      scopes: MapSet.new([@scope]),
      registration: platform.registration,
      req_options: [plug: {Req.Test, AttendanceService}],
      endpoints: %{
        AttendanceService => %AttendanceEndpoint{attendance_url: @attendance_url}
      }
    }
  end

  test "get_records/1 returns attendance records", %{platform: platform} do
    Req.Test.stub(AttendanceService, fn conn ->
      Req.Test.json(conn, %{
        "records" => [
          %{"user_id" => "user-1", "status" => "present"},
          %{"user_id" => "user-2", "status" => "absent"}
        ]
      })
    end)

    client = build_client(platform)
    assert {:ok, records} = AttendanceService.get_records(client)
    assert length(records) == 2
  end
end
```

The key pattern: construct a `%Client{}` directly with a hardcoded token
and `req_options: [plug: {Req.Test, AttendanceService}]`. This routes
your service's Req calls through `Req.Test` stubs registered under
`AttendanceService`, without hitting the OAuth token endpoint.

To test authentication itself, use `Ltix.Test.stub_token_response/1`:

```elixir
test "authenticate from launch context", %{platform: platform} do
  Ltix.Test.stub_token_response(
    scopes: [@scope],
    access_token: "test-attendance-token"
  )

  context = Ltix.Test.build_launch_context(platform)
  # Manually inject the parsed claim into extensions
  endpoint = %AttendanceEndpoint{attendance_url: @attendance_url}
  claims = %{context.claims | extensions: Map.put(
    context.claims.extensions,
    AttendanceEndpoint.claim_key(),
    endpoint
  )}
  context = %{context | claims: claims}

  {:ok, client} = Ltix.OAuth.authenticate(context.registration,
    endpoints: %{AttendanceService => endpoint}
  )

  assert client.access_token == "test-attendance-token"
end
```

## Combining with built-in services

Request all scopes in a single token by passing multiple endpoints:

```elixir
{:ok, client} = Ltix.OAuth.authenticate(registration,
  endpoints: %{
    Ltix.GradeService => ags_endpoint,
    AttendanceService => attendance_endpoint
  }
)

# One client, both services
:ok = Ltix.GradeService.post_score(client, score)
{:ok, records} = AttendanceService.get_records(client)
```

## Next steps

- [Custom Claim Parsers](../custom-claim-parsers.md) for the full
  claim parser guide
- [Advantage Services](../advantage-services.md) for token management
  and multi-service patterns
- [Token Caching and Reuse](token-caching-and-reuse.md) for batch
  refreshing across courses
- `Ltix.AdvantageService` for the behaviour reference
- `Ltix.OAuth.Client` for the full token lifecycle API
