defprotocol Ltix.Registerable do
  @moduledoc """
  Protocol for extracting an `Ltix.Registration` from a custom struct.

  Implement this protocol on your own registration struct so that
  `Ltix.StorageAdapter` callbacks can return your struct directly.
  The library calls the protocol internally to extract the
  `Ltix.Registration` it needs for JWT verification, nonce management,
  and OAuth token requests. Your original struct is preserved in the
  `Ltix.LaunchContext` returned after a successful launch.

      defmodule MyApp.PlatformRegistration do
        defstruct [:id, :tenant_id, :issuer, :client_id,
                   :auth_endpoint, :jwks_uri, :token_endpoint, :tool_jwk]

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

  `Ltix.Registration` itself implements this protocol as an identity
  transform, so existing code that returns `%Registration{}` from storage
  adapter callbacks continues to work.
  """

  @doc """
  Extract an `Ltix.Registration` from the given struct.

  Implementations should typically delegate to `Ltix.Registration.new/1`
  so that field validation is applied.
  """
  @spec to_registration(t()) :: {:ok, Ltix.Registration.t()} | {:error, Exception.t()}
  def to_registration(source)
end
