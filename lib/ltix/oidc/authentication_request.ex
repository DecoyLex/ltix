defmodule Ltix.OIDC.AuthenticationRequest do
  @moduledoc false

  alias Ltix.Registration

  # [Sec §5.1.1.2](https://www.imsglobal.org/spec/security/v1p0/#step-2-authentication-request)
  @spec build(Registration.t(), map()) :: String.t()
  def build(%Registration{} = registration, params) do
    query_params =
      [
        {"scope", "openid"},
        {"response_type", "id_token"},
        {"client_id", registration.client_id},
        {"redirect_uri", params.redirect_uri},
        {"login_hint", params.login_hint},
        {"state", params.state},
        {"response_mode", "form_post"},
        {"nonce", params.nonce},
        {"prompt", "none"}
      ]
      |> maybe_add("lti_message_hint", Map.get(params, :lti_message_hint))

    registration.auth_endpoint
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(query_params))
    |> URI.to_string()
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, value), do: params ++ [{key, value}]
end
