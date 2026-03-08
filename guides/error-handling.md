# Error Handling

When a launch fails, you need to know what went wrong and how to
respond. Ltix returns `{:error, exception}` from both `handle_login/3`
and `handle_callback/3`, with errors organized into three classes using
[Splode](https://hexdocs.pm/splode). You can match on the category
without knowing every individual error type.

## Error classes

| Class | Module | Meaning |
|---|---|---|
| `:invalid` | `Ltix.Errors.Invalid` | Bad input — malformed JWT, missing claims, unknown registration |
| `:security` | `Ltix.Errors.Security` | Security violation — bad signature, expired token, nonce replay |
| `:unknown` | `Ltix.Errors.Unknown` | Unexpected failure — network errors, bugs |

## Matching on class

Use `Ltix.Errors.class/1` to branch on the error category:

```elixir
case Ltix.handle_callback(params, state) do
  {:ok, context} ->
    handle_launch(conn, context)

  {:error, error} ->
    case Ltix.Errors.class(error) do
      :invalid ->
        conn |> put_status(400) |> text("Bad request: #{Exception.message(error)}")

      :security ->
        conn |> put_status(401) |> text("Unauthorized: #{Exception.message(error)}")

      :unknown ->
        Logger.error("LTI launch failed: #{Exception.message(error)}")
        conn |> put_status(500) |> text("Internal error")
    end
end
```

## Matching on specific errors

For finer control, match on the error struct directly:

```elixir
case Ltix.handle_login(params, launch_url) do
  {:ok, result} ->
    # ...

  {:error, %Ltix.Errors.Invalid.RegistrationNotFound{issuer: issuer}} ->
    Logger.warning("Unknown platform attempted login: #{issuer}")
    conn |> put_status(404) |> text("Platform not registered")

  {:error, %Ltix.Errors.Invalid.MissingParameter{parameter: param}} ->
    conn |> put_status(400) |> text("Missing required parameter: #{param}")

  {:error, error} ->
    conn |> put_status(400) |> text(Exception.message(error))
end
```

## Error messages and spec references

Every error produces a human-readable message via `Exception.message/1`
and most carry a `spec_ref` field pointing to the violated spec section:

```elixir
error = %Ltix.Errors.Security.TokenExpired{spec_ref: "Sec §5.1.3 step 5"}

Exception.message(error)
#=> "JWT token has expired [Sec §5.1.3 step 5]"

error.spec_ref
#=> "Sec §5.1.3 step 5"
```

The spec reference is useful for debugging — it tells you exactly which
validation step failed.

## Invalid errors

These indicate problems with the incoming data:

| Error | Fields | When |
|---|---|---|
| `MissingParameter` | `parameter`, `spec_ref` | OIDC login request missing a required param |
| `MissingClaim` | `claim`, `spec_ref` | JWT missing a required claim |
| `InvalidClaim` | `claim`, `value`, `spec_ref` | JWT claim has an invalid value |
| `InvalidJson` | `spec_ref` | JWT body isn't valid JSON |
| `RegistrationNotFound` | `issuer`, `client_id` | No registration matches the issuer |
| `DeploymentNotFound` | `deployment_id` | No deployment matches the JWT's deployment_id |

## Security errors

These indicate the launch failed a security check:

| Error | Fields | When |
|---|---|---|
| `SignatureInvalid` | `spec_ref` | JWT signature doesn't verify against the platform's public key |
| `TokenExpired` | `spec_ref` | JWT `exp` claim is in the past |
| `IssuerMismatch` | `expected`, `actual`, `spec_ref` | JWT `iss` doesn't match the registration |
| `AudienceMismatch` | `expected`, `actual`, `spec_ref` | Registration's client_id not in JWT `aud` |
| `AlgorithmNotAllowed` | `algorithm`, `spec_ref` | JWT uses something other than RS256 |
| `StateMismatch` | `spec_ref` | OIDC state from callback doesn't match the session |
| `NonceMissing` | `spec_ref` | JWT has no `nonce` claim |
| `NonceNotFound` | `spec_ref` | Nonce wasn't issued by this tool |
| `NonceReused` | `spec_ref` | Nonce was already consumed (replay attempt) |
| `KidMissing` | `spec_ref` | JWT header has no `kid` field |
| `KidNotFound` | `kid`, `spec_ref` | `kid` not found in the platform's JWKS |
| `AuthenticationFailed` | `error`, `error_description`, `spec_ref` | Platform returned an error response |

## Logging recommendations

Invalid errors are usually the platform's fault (misconfiguration,
bad requests). Security errors could be attacks or clock skew. Unknown
errors need investigation:

```elixir
{:error, error} ->
  case Ltix.Errors.class(error) do
    :invalid ->
      Logger.info("LTI invalid request: #{Exception.message(error)}")

    :security ->
      Logger.warning("LTI security violation: #{Exception.message(error)}")

    :unknown ->
      Logger.error("LTI unexpected error: #{Exception.message(error)}")
  end
```
