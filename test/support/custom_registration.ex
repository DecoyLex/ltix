defmodule CustomRegistration do
  @moduledoc false

  # Intentionally different shape from %Ltix.Registration{}. Uses
  # DB-style field names and includes app-specific fields that
  # %Ltix.Registration{} doesn't have.

  defstruct [
    :id,
    :tenant_id,
    :platform_issuer,
    :oauth_client_id,
    :oidc_auth_url,
    :platform_jwks_url,
    :platform_token_url
  ]

  # Builds a record with a unique ID and key set URL. `attributes` replace
  # the defaults, and the endpoint URLs default to paths on the issuer.
  def new(attributes \\ []) do
    issuer = Keyword.get(attributes, :platform_issuer, "https://custom-lms.example.com")
    unique = System.unique_integer([:positive])

    defaults = [
      id: unique,
      platform_issuer: issuer,
      oauth_client_id: "custom-tool-client",
      oidc_auth_url: "#{issuer}/auth",
      platform_jwks_url: "#{issuer}/.well-known/jwks-#{unique}.json",
      platform_token_url: "#{issuer}/token"
    ]

    struct!(__MODULE__, Keyword.merge(defaults, attributes))
  end

  # Builds the record an application stores for `registration`.
  def from_registration(%Ltix.Registration{} = registration, attributes \\ []) do
    registration_attributes = [
      platform_issuer: registration.issuer,
      oauth_client_id: registration.client_id,
      oidc_auth_url: registration.auth_endpoint,
      platform_jwks_url: registration.jwks_uri,
      platform_token_url: registration.token_endpoint
    ]

    new(Keyword.merge(registration_attributes, attributes))
  end

  defimpl Ltix.Registerable do
    def to_registration(reg) do
      Ltix.Registration.new(%{
        issuer: reg.platform_issuer,
        client_id: reg.oauth_client_id,
        auth_endpoint: reg.oidc_auth_url,
        jwks_uri: reg.platform_jwks_url,
        token_endpoint: reg.platform_token_url
      })
    end
  end
end
