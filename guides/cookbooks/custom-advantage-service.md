# Building a Custom Advantage Service

Some platforms expose proprietary APIs alongside standard LTI services. You can use these with Ltix's OAuth flow by implementing the `Ltix.AdvantageService` behaviour, giving your custom service the same authentication and token management as built-in services like `Ltix.GradeService` and `Ltix.MembershipsService`.

This cookbook builds a client for a fictional Attendance service. The platform tracks class attendance and exposes a read-only API to query attendance records for a course.

## Endpoint claim

Start with the endpoint claim the platform sends in the launch JWT. The Attendance service has one URL and one scope. Declare the claim with `Ltix.Claim`, and set `:service` to the service its endpoint belongs to.

```elixir
# lib/my_app/lti/attendance_endpoint.ex
defmodule MyApp.Lti.AttendanceEndpoint do
  use Ltix.Claim,
    claim: "https://lms.example.com/claim/attendance",
    name: :attendance_endpoint,
    strict: false,
    service: MyApp.Lti.AttendanceService,
    fields: [attendance_url: Zoi.string()]
end
```

`use Ltix.Claim` builds the `%MyApp.Lti.AttendanceEndpoint{}` struct from the fields and parses the claim into it. `strict: false` makes a malformed claim `nil` in the launch's claims, so a platform's malformed attendance claim doesn't fail the launch. See [Writing Plugins](../writing-plugins.md) for declared claims.

## Plugin

A plugin adds the claim to every launch.

```elixir
# lib/my_app/lti/attendance.ex
defmodule MyApp.Lti.Attendance do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.add(Ltix.Plugin.new(name: "Attendance"), MyApp.Lti.AttendanceEndpoint)
  end
end
```

```elixir
# config/config.exs
config :ltix, plugins: [MyApp.Lti.Attendance]
```

`Ltix.Launch.get_endpoint/2` now returns a launch's endpoint for the service.

```elixir
Ltix.Launch.get_endpoint(launch, MyApp.Lti.AttendanceService)
#=> %MyApp.Lti.AttendanceEndpoint{attendance_url: "https://lms.example.com/api/attendance/ctx-123"}
```

## Service module

Implement the `Ltix.AdvantageService` behaviour. `Ltix.OAuth` calls the callbacks to validate your endpoint and get the scopes to request.

```elixir
# lib/my_app/lti/attendance_service.ex
defmodule MyApp.Lti.AttendanceService do
  @behaviour Ltix.AdvantageService

  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias MyApp.Lti.AttendanceEndpoint

  @scope "https://lms.example.com/scope/attendance.readonly"

  @impl true
  def validate_endpoint(%AttendanceEndpoint{}), do: :ok
  def validate_endpoint(_), do: {:error, InvalidEndpoint.exception(service: __MODULE__)}

  @impl true
  def scopes(%AttendanceEndpoint{}), do: [@scope]
end
```

## Authenticating

With the behaviour implemented, authenticate through `Ltix.OAuth`.

**From a launch**

```elixir
alias MyApp.Lti.AttendanceService

def handle_launch(launch) do
  {:ok, client} = Ltix.OAuth.authenticate(launch, services: [AttendanceService])
  {:ok, records} = AttendanceService.get_records(client)
end
```

`Ltix.OAuth` reads the endpoint from the launch. If the launch has no attendance claim, `authenticate/2` returns a `Ltix.Errors.Invalid.ServiceNotAvailable` error.

**From a stored endpoint** (background job, no launch)

```elixir
endpoint = %AttendanceEndpoint{attendance_url: stored_url}

{:ok, client} = Ltix.OAuth.authenticate(registration,
  endpoints: %{AttendanceService => endpoint}
)
```

Both paths produce the same `%Ltix.OAuth.Client{}`. Its `endpoints` map has your endpoint, keyed by `AttendanceService`.

## Making authenticated requests

Send requests with `Ltix.OAuth.Client.request/3`. It adds the client's bearer token and applies the checks Ltix makes on every platform request, such as HTTPS and the client's `:local_network_access` setting. The platform may grant fewer scopes than requested, so check the scope first. `Ltix.OAuth.Client.require_scope/2` returns `Ltix.Errors.Invalid.ScopeMismatch` when the token lacks it.

```elixir
# lib/my_app/lti/attendance_service.ex

alias Ltix.OAuth.Client

@spec get_records(Client.t()) :: {:ok, [map()]} | {:error, Exception.t()}
def get_records(%Client{} = client) do
  endpoint = client.endpoints[__MODULE__]

  with :ok <- Client.require_scope(client, @scope),
       {:ok, %Req.Response{body: body}} <-
         Client.request(client, __MODULE__,
           url: endpoint.attendance_url,
           headers: [{"accept", "application/json"}]
         ) do
    {:ok, body["records"]}
  end
end
```

The options are `Req` request options. The endpoint URL comes from `client.endpoints[__MODULE__]`.

A response with an error status returns an error. A 401 or 403 is `Ltix.Errors.Security.AccessDenied`, and any other status is `Ltix.Errors.Unknown.TransportError`.

## Paginated requests

If the platform splits a collection across pages with `Link` headers, use `Ltix.OAuth.Client.request_pages/3`. It takes the same options, sends each page's request the same way, and returns a stream with `{:ok, body}` or `{:error, error}` for each page. Pages are fetched as you consume the stream.

```elixir
@spec stream_records(Client.t()) :: {:ok, Enumerable.t()} | {:error, Exception.t()}
def stream_records(%Client{} = client) do
  endpoint = client.endpoints[__MODULE__]

  with :ok <- Client.require_scope(client, @scope),
       {:ok, pages} <-
         Client.request_pages(client, __MODULE__,
           url: endpoint.attendance_url,
           params: [limit: 50],
           headers: [{"accept", "application/json"}]
         ) do
    {:ok,
     Stream.flat_map(pages, fn
       {:ok, body} -> body["records"]
       {:error, error} -> raise error
     end)}
  end
end
```

## Adding an expiry check

Tokens expire after about an hour. For request handlers that authenticate and immediately call the service, this isn't a concern. For longer-lived processes, check before each call.

```elixir
def get_records(%Client{} = client) do
  with :ok <- Client.require_unexpired(client) do
    do_get_records(client)
  end
end
```

Or refresh automatically.

```elixir
client = Client.refresh!(client)
```

See [Token Caching and Reuse](token-caching-and-reuse.md) for patterns around batch refreshing and ETS caching.

## Testing

Test your service the same way Ltix tests its built-in services. Stub the token endpoint and your service's HTTP calls with `Req.Test`.

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
      token: %Ltix.OAuth.AccessToken{
        access_token: "test-attendance-token",
        token_type: "bearer",
        granted_scopes: MapSet.new([@scope]),
        expires_at: DateTime.add(DateTime.utc_now(), 3600)
      },
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

Construct a `%Client{}` directly with a hardcoded token and `req_options: [plug: {Req.Test, AttendanceService}]`. `Ltix.OAuth.Client.request/3` sends your service's requests to the `Req.Test` stub registered under the service module, without calling the OAuth token endpoint.

To test authentication itself, use `Ltix.Test.stub_token_response/1`. Pass the attendance claim to `Ltix.Test.build_launch/2` with `:claims`, and your plugin turns it into the endpoint struct.

```elixir
test "authenticate from launch", %{platform: platform} do
  Ltix.Test.stub_token_response(
    scopes: [@scope],
    access_token: "test-attendance-token"
  )

  launch =
    Ltix.Test.build_launch(platform,
      claims: %{"https://lms.example.com/claim/attendance" => %{"attendance_url" => @attendance_url}}
    )

  {:ok, client} = Ltix.OAuth.authenticate(launch, services: [AttendanceService])

  assert client.token.access_token == "test-attendance-token"
end
```

## Combining with built-in services

Request all scopes in a single token by passing multiple endpoints.

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

From a launch, list the services.

```elixir
{:ok, client} = Ltix.OAuth.authenticate(launch,
  services: [Ltix.GradeService, AttendanceService]
)
```

## Next steps

- [Advantage Services](../advantage-services.md) for token management and multi-service patterns
- [Token Caching and Reuse](token-caching-and-reuse.md) for batch refreshing across courses
- `Ltix.AdvantageService` for the behaviour reference
- `Ltix.OAuth.Client` for the full token lifecycle API
