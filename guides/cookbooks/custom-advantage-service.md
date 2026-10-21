# Building a Custom Advantage Service

Some platforms expose proprietary APIs alongside standard LTI services. You can use these with Ltix's OAuth flow by writing a service plugin, giving your custom service the same authentication and token management as built-in services like `Ltix.GradeService` and `Ltix.MembershipsService`.

This cookbook builds a client for a fictional Attendance service. The platform tracks class attendance and exposes a read-only API to query attendance records for a course.

## Endpoint claim

The platform sends the service's endpoint in a launch claim. Declare it with `Ltix.Claim`, set `:service` to the service module, and build and check the endpoint in `c:Ltix.Claim.new/1`. Add `{:zoi, "~> 0.17"}` to your dependencies for the field schemas.

```elixir
# lib/my_app/lti/attendance_endpoint.ex
defmodule MyApp.Lti.AttendanceEndpoint do
  use Ltix.Claim,
    claim: "https://lms.example.com/claim/attendance",
    name: :attendance_endpoint,
    strict: false,
    service: MyApp.Lti.AttendanceService,
    fields: [attendance_url: Zoi.string()]

  alias Ltix.Errors.Invalid.InvalidField

  @impl Ltix.Claim
  def new(attributes) do
    case attributes[:attendance_url] do
      "https://" <> _rest = url ->
        {:ok, %__MODULE__{attendance_url: url}}

      url ->
        {:error,
         InvalidField.exception(
           struct: __MODULE__,
           field: :attendance_url,
           value: url,
           reason: "must be an HTTPS URL"
         )}
    end
  end
end
```

The claim is declared with [`strict: false`](../writing-claim-and-launch-plugins.md#malformed-and-missing-claims), so a malformed endpoint claim is `nil` and doesn't fail the launch. `authenticate/2` checks every endpoint with `new/1`, including endpoints you stored.

## Scope

A [client assertion step](../writing-advantage-service-plugins.md#add-the-service-s-scope-to-token-requests) adds the service's scope to token requests for it.

```elixir
# lib/my_app/lti/attendance_scope.ex
defmodule MyApp.Lti.AttendanceScope do
  use Ltix.ClientAssertion

  alias MyApp.Lti.AttendanceService

  @impl Ltix.Step
  def call(%{endpoints: %{AttendanceService => _endpoint}} = assertion, _opts) do
    {:ok, update_in(assertion.scopes, &(&1 ++ [AttendanceService.scope()]))}
  end

  def call(assertion, _opts), do: {:ok, assertion}
end
```

## Plugin

```elixir
# lib/my_app/lti/attendance.ex
defmodule MyApp.Lti.Attendance do
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Attendance")
    |> Ltix.Plugin.add(MyApp.Lti.AttendanceEndpoint)
    |> Ltix.Plugin.add(MyApp.Lti.AttendanceScope)
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

## Authenticating

From a launch, pass the service as `services:`. When the launch has no attendance claim, `authenticate/2` returns `Ltix.Errors.Invalid.ServiceNotAvailable`.

```elixir
alias MyApp.Lti.AttendanceService

{:ok, client} = Ltix.OAuth.authenticate(launch, services: [AttendanceService])
{:ok, records} = AttendanceService.get_records(client)
```

From a URL stored during a launch, rebuild the endpoint and pass your registration and deployment records.

```elixir
{:ok, endpoint} = MyApp.Lti.AttendanceEndpoint.new(attendance_url: stored_url)

{:ok, client} =
  Ltix.OAuth.authenticate(registration,
    endpoints: %{AttendanceService => endpoint},
    deployment: deployment
  )
```

## Making authenticated requests

Send requests with `Ltix.OAuth.Client.request/3`. It adds the client's bearer token and applies the checks Ltix makes on every platform request, such as HTTPS and the client's `:local_network_access` setting. The platform may grant fewer scopes than requested, so check the scope first. `Ltix.OAuth.Client.require_scope/2` returns `Ltix.Errors.Invalid.ScopeMismatch` when the token lacks it.

```elixir
# lib/my_app/lti/attendance_service.ex
defmodule MyApp.Lti.AttendanceService do
  alias Ltix.OAuth.Client

  @scope "https://lms.example.com/scope/attendance.readonly"

  @spec scope() :: String.t()
  def scope, do: @scope

  @spec get_records(Client.t()) :: {:ok, [map()]} | {:error, Exception.t()}
  def get_records(%Client{} = client) do
    endpoint = Client.get_endpoint(client, __MODULE__)

    with :ok <- Client.require_scope(client, @scope),
         {:ok, %Req.Response{body: body}} <-
           Client.request(client, __MODULE__,
             url: endpoint.attendance_url,
             headers: [{"accept", "application/json"}]
           ) do
      {:ok, body["records"]}
    end
  end
end
```

The options are `Req` request options. The URL comes from the endpoint that `Ltix.OAuth.Client.get_endpoint/2` returns.

A response with an error status returns an error. A 401 or 403 is `Ltix.Errors.Security.AccessDenied`, and any other status is `Ltix.Errors.Unknown.TransportError`.

## Paginated requests

If the platform splits a collection across pages with `Link` headers, use `Ltix.OAuth.Client.request_pages/3`. It takes the same options, sends each page's request the same way, and returns a stream with `{:ok, body}` or `{:error, error}` for each page. Pages are fetched as you consume the stream.

```elixir
@spec stream_records(Client.t()) :: {:ok, Enumerable.t()} | {:error, Exception.t()}
def stream_records(%Client{} = client) do
  endpoint = Client.get_endpoint(client, __MODULE__)

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
- `Ltix.OAuth.Client` for the full token lifecycle API
