# Custom Claim Parsers

Ltix parses standard OIDC and LTI claims from the launch JWT
automatically. Any unrecognized claims land in the `extensions` map as
raw values:

```elixir
context.claims.extensions
#=> %{"https://myplatform.example.com/claim/analytics" => %{"session_id" => "abc123"}}
```

Register custom claim parsers to transform these raw values into
structured data.

## Writing a claim parser

A claim parser is any function that takes a raw claim value and returns
`{:ok, parsed}` or `{:error, reason}`. There is no behaviour to
implement:

```elixir
defmodule MyApp.Lti.AnalyticsClaim do
  defstruct [:session_id, :tracking_enabled]

  def parse(%{"session_id" => session_id} = raw) do
    {:ok,
     %__MODULE__{
       session_id: session_id,
       tracking_enabled: Map.get(raw, "tracking_enabled", false)
     }}
  end

  def parse(_), do: {:error, "missing session_id in analytics claim"}
end
```

## Registering parsers

Claim parsers are registered as a map of claim key to parser function.
The key is the full claim name as it appears in the JWT (usually a
namespaced URI for extension claims).

**Via application config** (recommended for parsers that apply globally):

```elixir
# config/config.exs
config :ltix, Ltix.LaunchClaims,
  claim_parsers: %{
    "https://myplatform.example.com/claim/analytics" =>
      &MyApp.Lti.AnalyticsClaim.parse/1
  }
```

**Via `handle_callback/3`** (for per-call control):

```elixir
Ltix.handle_callback(params, state,
  claim_parsers: %{
    "https://myplatform.example.com/claim/analytics" =>
      &MyApp.Lti.AnalyticsClaim.parse/1
  }
)
```

**Via `LaunchClaims.from_json/2`** (for direct parsing):

```elixir
Ltix.LaunchClaims.from_json(claims,
  parsers: %{
    "https://myplatform.example.com/claim/analytics" =>
      &MyApp.Lti.AnalyticsClaim.parse/1
  }
)
```

Per-call parsers merge with application config, with per-call taking
priority for overlapping keys.

## Accessing parsed claims

Parsed extension claims remain in the `extensions` map, but with your
parsed values instead of raw maps:

```elixir
{:ok, context} = Ltix.handle_callback(params, state)

context.claims.extensions["https://myplatform.example.com/claim/analytics"]
#=> %MyApp.Lti.AnalyticsClaim{session_id: "abc123", tracking_enabled: true}
```

## Error handling

If a claim parser returns `{:error, reason}`, the entire launch fails
with that error. Only register parsers for claims you require. If a
claim is optional, handle the missing case gracefully in your parser:

```elixir
def parse(nil), do: {:ok, nil}
def parse(%{"session_id" => _} = raw), do: {:ok, to_struct(raw)}
def parse(_), do: {:error, "invalid analytics claim"}
```

## Registering multiple parsers

You can register claim parsers and role parsers together in application
config:

```elixir
config :ltix, Ltix.LaunchClaims,
  role_parsers: %{
    "https://myplatform.example.com/roles/" => MyApp.Lti.PlatformRoleParser
  },
  claim_parsers: %{
    "https://myplatform.example.com/claim/analytics" =>
      &MyApp.Lti.AnalyticsClaim.parse/1,
    "https://myplatform.example.com/claim/proctoring" =>
      &MyApp.Lti.ProctoringClaim.parse/1
  }
```

## Next steps

- [Custom Role Parsers](custom-role-parsers.md) for handling
  proprietary role vocabularies
- `Ltix.LaunchClaims` for the full claims struct and `from_json/2` options
- [Error Handling](error-handling.md) for how parser errors surface
