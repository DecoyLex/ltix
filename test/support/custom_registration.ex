defmodule CustomRegistration do
  @moduledoc false

  defstruct [:id, :tenant_id, :issuer, :client_id, :auth_endpoint, :jwks_uri, :token_endpoint, :tool_jwk]

  defimpl Ltix.Registerable do
    def to_registration(reg) do
      Ltix.Registration.new(%{
        issuer: reg.issuer,
        client_id: reg.client_id,
        auth_endpoint: reg.auth_endpoint,
        jwks_uri: reg.jwks_uri,
        token_endpoint: reg.token_endpoint,
        tool_jwk: reg.tool_jwk
      })
    end
  end
end
