defmodule CustomRegistration do
  @moduledoc false

  # Intentionally different shape from %Ltix.Registration{} — uses
  # DB-style field names and includes app-specific fields that Ltix
  # doesn't know about.

  defstruct [
    :id,
    :tenant_id,
    :platform_issuer,
    :oauth_client_id,
    :oidc_auth_url,
    :platform_jwks_url,
    :platform_token_url,
    :signing_key
  ]

  defimpl Ltix.Registerable do
    def to_registration(reg) do
      Ltix.Registration.new(%{
        issuer: reg.platform_issuer,
        client_id: reg.oauth_client_id,
        auth_endpoint: reg.oidc_auth_url,
        jwks_uri: reg.platform_jwks_url,
        token_endpoint: reg.platform_token_url,
        tool_jwk: reg.signing_key
      })
    end
  end
end
