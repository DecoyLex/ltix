# Hardening Your Tool

Ltix authenticates launches and checks the requests it sends to platforms. The rest of your tool's security is your application's job. This guide lists what to do, with the code for each step. For what Ltix itself guarantees, see the [Threat Model](threat-model.md).

## Sessions and login state

`Ltix.handle_login/3` returns a state value. Keep it in the user's session and pass that session value to `Ltix.handle_callback/3`. Don't read the expected state from the launch request, because then anyone can supply a matching pair.

```elixir
def login(conn, params) do
  {:ok, %{redirect_uri: url, state: state}} = Ltix.handle_login(params, launch_url)

  conn
  |> put_session(:lti_state, state)
  |> redirect(external: url)
end

def launch(conn, params) do
  state = get_session(conn, :lti_state)

  case Ltix.handle_callback(params, state) do
    {:ok, context} ->
      conn
      |> delete_session(:lti_state)
      |> start_session(context)

    {:error, error} ->
      launch_failed(conn, error)
  end
end
```

Launches usually arrive inside the platform's iframe as a cross-site POST, so the session cookie needs three attributes.

```elixir
plug Plug.Session,
  store: :cookie,
  key: "_my_app_key",
  signing_salt: "your-salt",
  same_site: "None",
  secure: true,
  extra: "Partitioned"
```

- `SameSite=None` lets the browser send the cookie on the platform's POST.
- `Secure` is required with `SameSite=None`.
- `Partitioned` keeps the cookie working in browsers that block third-party cookies, and gives each platform site its own cookie jar.

For browsers that block the cookie, see [Keeping Login State in Platform Storage](cookbooks/platform-storage.md).

Sign the session cookie, which Phoenix does by default. Add `:encryption_salt` if you keep anything in it that the user shouldn't read.

## Launches

An `Ltix.Launch` has the user's identity, roles, and context data. Keep launches in a server-side store with an expiry, and put only an ID in the session. A signed cookie can be read by the user, and a launch is too large for one.

## After the launch

The state and nonce checks protect only the launch request. Every route your tool serves afterward needs its own protection.

### CSRF

The launch route can't use Phoenix's CSRF protection, because the platform sends the POST. Put the routes users reach after the launch in a pipeline that has it.

```elixir
pipeline :lti_launch do
  plug :accepts, ["html"]
  plug :fetch_session
end

pipeline :lti do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :protect_from_forgery
end
```

### Authorization

Decide what a user may do from the roles in the verified launch.

```elixir
alias Ltix.Role

if Role.instructor?(launch.claims.roles) do
  # show grading tools
end
```

Platforms report roles differently, so check the broad role your feature needs. See [Working with Roles](working-with-roles.md).

### Data from later requests

Take the context, resource link, and service endpoints a user acts on from the launch you stored. Don't accept them from form fields or query parameters. A line item URL from the browser, for example, sends your platform access token to whatever URL the user supplies.

```elixir
# The line item comes from the stored launch, never from params
{:ok, client} = Ltix.GradeService.authenticate(context)
:ok = Ltix.GradeService.post_score(client, score)
```

### Rendering claims

Names, titles, and custom claims are platform data. Render them through HEEx or another escaping template, and treat URLs in claims as untrusted links.

### Framing

Your tool has to allow the platform to frame it. If you know each platform's origin, restrict `frame-ancestors` to it after the launch.

```elixir
plug :put_secure_browser_headers, %{
  "content-security-policy" => "frame-ancestors 'self' https://canvas.example.edu"
}
```

## Redirects

`launch.claims.target_link_uri` is the URL the platform requests as the user's destination. Check that it points at your tool before redirecting, so a launch can't send users to another site through your domain.

```elixir
defp tool_url?(url) do
  target = URI.parse(url)
  endpoint = MyAppWeb.Endpoint.struct_url()

  {target.scheme, target.host, target.port} == {endpoint.scheme, endpoint.host, endpoint.port}
end
```

## Registering platforms

Registering a platform is the decision to trust it. Ltix accepts what a registered platform signs.

- Have a person approve each registration. If you offer self-service or dynamic registration, hold new registrations until someone approves them.
- Look registrations up by issuer and client ID. For a login that leaves out the client ID, return `{:error, :not_found}` when the issuer has more than one registration.
- Scope deployments to their registration, so one platform's deployment ID can't match another's.

## Storage adapter

Your adapter's `c:Ltix.StorageAdapter.validate_nonce/4` has to accept each nonce only once, even when two launches arrive at the same moment. Use an atomic insert, and delete records after their `expires_at`. See [Storage Adapters](storage-adapters.md#nonce-management).

Run `Ltix.Test.assert_storage_adapter!/2` against your adapter in your test suite. It checks registration and deployment scoping, concurrent nonce use, and signatures.

## Signing keys

Ltix calls your adapter for each signature and never stores your private key.

- Keep keys out of version control, logs, and responses. Encrypt them at rest, or keep them in a key management service and sign from `sign/4`.
- Use a separate key for each registration, so you can rotate one without the others.
- Serve your key set endpoint from public keys. `Ltix.JWK.new/1` builds a JWK from a public key alone, and `Ltix.JWK.to_jwks/1` returns only public keys.
- In `sign/4`, sign with the key whose ID is the `key_id` argument, and return an error for an ID you don't have.

See [JWK Management](jwk-management.md) for rotation.

## Platform requests

Ltix sends requests only to public addresses, over HTTPS, with certificate verification.

- Leave `:local_network_access` at its default in production. Grant `:local` or `:loopback` on the call for a platform you know runs on your network, and avoid granting it in config for every platform.
- Don't pass `:finch`, `:adapter`, `:unix_socket`, or a proxy in `:req_options` unless you need one. Ltix can't check the addresses they connect to, so they need `local_network_access: :loopback`. With a proxy, have the proxy block private addresses.
- Send a custom Advantage service's requests with `Ltix.OAuth.Client.request/3` and `Ltix.OAuth.Client.request_pages/3`, which apply these checks. Requests your own code sends directly with `Req` don't get them.

Access tokens from `Ltix.OAuth` let the holder call the platform as your tool. Cache them on the server and keep them out of logs and responses.

## Errors and logging

Show users a general message when a launch fails, and log the error. Error messages can include URLs and claim values.

```elixir
{:error, error} ->
  Logger.warning("LTI launch failed: #{Exception.message(error)}")

  conn
  |> put_status(Ltix.Errors.status_code(error))
  |> render(:error, message: "The launch could not be completed.")
```

Watch for repeated `Ltix.Errors.Security` errors. See [Error Handling](error-handling.md#logging-recommendations) and [Telemetry](telemetry.md).

## Rate limiting

Your login and launch endpoints accept requests from anyone. Rate limit them the way you would any public endpoint.

## Next steps

- [Threat Model](threat-model.md) - what Ltix guarantees and what is out of scope
- [Storage Adapters](storage-adapters.md) - nonce storage and signing callbacks
- [JWK Management](jwk-management.md) - generating and rotating keys
- [Getting Started](getting-started.md) - session, pipeline, and iframe setup
- [Error Handling](error-handling.md) - matching and logging errors
