defprotocol Ltix.Registerable do
  @moduledoc """
  Protocol for converting your registration struct to an `Ltix.Registration`.

  Implement it for your registration struct, and your storage adapter can
  return that struct. Ltix passes your struct to the other
  `Ltix.StorageAdapter` callbacks. It's in `source_registration` on an
  `Ltix.Login` and an `Ltix.Launch`, and in `registration` on an
  `Ltix.OAuth.Client`.

      defmodule MyApp.PlatformRegistration do
        defstruct [:id, :tenant_id, :issuer, :client_id,
                   :auth_endpoint, :jwks_uri, :token_endpoint]

        defimpl Ltix.Registerable do
          def to_registration(reg) do
            Ltix.Registration.new(%{
              issuer: reg.issuer,
              client_id: reg.client_id,
              auth_endpoint: reg.auth_endpoint,
              jwks_uri: reg.jwks_uri,
              token_endpoint: reg.token_endpoint
            })
          end
        end
      end

  `Ltix.Registration` implements this protocol, so your storage adapter can
  also return a `%Registration{}`. Login and launch return the same error as
  `Ltix.Registration.new/1` for an invalid one.
  """

  @doc """
  Return the `Ltix.Registration` for the given struct.

  Build it with `Ltix.Registration.new/1`, which validates the fields.
  """
  @spec to_registration(t()) :: {:ok, Ltix.Registration.t()} | {:error, Exception.t()}
  def to_registration(source)
end
