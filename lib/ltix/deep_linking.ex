defmodule Ltix.DeepLinking do
  @moduledoc """
  Package content items into a signed response JWT for the platform.

  When the platform sends an `LtiDeepLinkingRequest` launch, your tool
  presents a selection UI and calls `build_response/3` with the chosen
  items. The response JWT is then POSTed back to the platform's return URL.

  Content items are built with these modules:

    * `Ltix.DeepLinking.ContentItem.LtiResourceLink` — an LTI activity
      the platform will link to
    * `Ltix.DeepLinking.ContentItem.Link` — an external URL
    * `Ltix.DeepLinking.ContentItem.File` — a downloadable file
    * `Ltix.DeepLinking.ContentItem.HtmlFragment` — inline HTML to embed
    * `Ltix.DeepLinking.ContentItem.Image` — an image for direct rendering

  See the [Deep Linking](deep-linking.md) guide for the full workflow
  and [Building Content Items](cookbooks/building-content-items.md) for
  recipes.
  """

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItem.LtiResourceLink
  alias Ltix.DeepLinking.Response

  alias Ltix.Deployable
  alias Ltix.LaunchContext
  alias Ltix.Registerable

  alias Ltix.Errors.Invalid.ContentItemsExceedLimit
  alias Ltix.Errors.Invalid.ContentItemTypeNotAccepted
  alias Ltix.Errors.Invalid.InvalidMessageType
  alias Ltix.Errors.Invalid.LineItemNotAccepted

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @dl "https://purl.imsglobal.org/spec/lti-dl/claim/"

  @opts_schema Zoi.keyword(
                 msg: Zoi.string() |> Zoi.optional(),
                 log: Zoi.string() |> Zoi.optional(),
                 error_message: Zoi.string() |> Zoi.optional(),
                 error_log: Zoi.string() |> Zoi.optional()
               )

  @doc """
  Build a signed Deep Linking response JWT.

  Takes a `LaunchContext` from an `LtiDeepLinkingRequest` launch, a list of
  content items, and optional message/log fields. Returns a `Response` with
  the signed JWT and the platform's return URL.

  ## Options

    * `:msg` — user-facing message to show on return
    * `:log` — log message for the platform
    * `:error_message` — user-facing error message
    * `:error_log` — error log message for the platform

  ## Errors

    * `Ltix.Errors.Invalid.InvalidMessageType` — context is not a deep
      linking launch
    * `Ltix.Errors.Invalid.ContentItemTypeNotAccepted` — item type not
      in `accept_types`
    * `Ltix.Errors.Invalid.ContentItemsExceedLimit` — multiple items
      when `accept_multiple` is `false`
    * `Ltix.Errors.Invalid.LineItemNotAccepted` — line item present
      when `accept_lineitem` is `false`

  ## Examples

      {:ok, link} = Ltix.DeepLinking.ContentItem.LtiResourceLink.new(
        url: "https://tool.example.com/activity/123",
        title: "Quiz 1"
      )

      {:ok, response} = Ltix.DeepLinking.build_response(context, [link],
        msg: "Selected 1 item"
      )

      # response.jwt — signed JWT to POST to response.return_url

  See the [Deep Linking](deep-linking.md) guide for the full workflow.
  """
  @spec build_response(LaunchContext.t(), list(), keyword()) ::
          {:ok, Response.t()} | {:error, Exception.t()}
  def build_response(context, items \\ [], opts \\ [])

  def build_response(
        %LaunchContext{claims: %{message_type: "LtiDeepLinkingRequest"}} = context,
        items,
        opts
      ) do
    settings = context.claims.deep_linking_settings

    with {:ok, opts} <- validate_opts(opts),
         {:ok, registration} <- Registerable.to_registration(context.registration),
         {:ok, deployment} <- Deployable.to_deployment(context.deployment),
         :ok <- validate_item_types(items, settings.accept_types),
         :ok <- validate_multiplicity(items, settings.accept_multiple),
         :ok <- validate_line_items(items, settings.accept_lineitem) do
      items_json = Enum.map(items, &ContentItem.to_json/1)
      claims = build_jwt_claims(registration, deployment, settings, items_json, opts)
      jwt = sign_jwt(claims, registration.tool_jwk)
      {:ok, %Response{jwt: jwt, return_url: settings.deep_link_return_url}}
    end
  end

  def build_response(%LaunchContext{claims: %{message_type: mt}}, _items, _opts) do
    {:error, InvalidMessageType.exception(message_type: mt, spec_ref: "DL §4.5")}
  end

  # --- Validation ---

  defp validate_opts(opts), do: Zoi.parse(@opts_schema, opts)

  defp validate_item_types(items, accept_types) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      type = ContentItem.item_type(item)

      if type in accept_types do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          ContentItemTypeNotAccepted.exception(
            type: type,
            accept_types: accept_types,
            spec_ref: "DL §4.4.1"
          )}}
      end
    end)
  end

  defp validate_multiplicity(items, accept_multiple) when accept_multiple == false do
    count = length(items)

    if count > 1 do
      {:error, ContentItemsExceedLimit.exception(count: count, spec_ref: "DL §4.4.1")}
    else
      :ok
    end
  end

  defp validate_multiplicity(_items, _accept_multiple), do: :ok

  defp validate_line_items(items, accept_lineitem) when accept_lineitem == false do
    has_line_item? =
      Enum.any?(items, fn
        %LtiResourceLink{line_item: li} when not is_nil(li) -> true
        _ -> false
      end)

    if has_line_item? do
      {:error, LineItemNotAccepted.exception(spec_ref: "DL §4.4.1")}
    else
      :ok
    end
  end

  defp validate_line_items(_items, _accept_lineitem), do: :ok

  # --- JWT Construction ---

  # [DL §4.5](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-response-message)
  # [Sec §5.2](https://www.imsglobal.org/spec/security/v1p0/#tool-originating-messages)
  defp build_jwt_claims(registration, deployment, settings, items_json, opts) do
    now = System.system_time(:second)

    %{
      "iss" => registration.client_id,
      "aud" => registration.issuer,
      "azp" => registration.issuer,
      "exp" => now + 300,
      "iat" => now,
      "nonce" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false),
      (@lti <> "deployment_id") => deployment.deployment_id,
      (@lti <> "message_type") => "LtiDeepLinkingResponse",
      (@lti <> "version") => "1.3.0",
      (@dl <> "content_items") => items_json
    }
    |> maybe_put(@dl <> "data", settings.data)
    |> maybe_put(@dl <> "msg", Keyword.get(opts, :msg))
    |> maybe_put(@dl <> "log", Keyword.get(opts, :log))
    |> maybe_put(@dl <> "errormsg", Keyword.get(opts, :error_message))
    |> maybe_put(@dl <> "errorlog", Keyword.get(opts, :error_log))
  end

  # [Sec §5.2.2](https://www.imsglobal.org/spec/security/v1p0/#tool-originating-messages)
  defp sign_jwt(claims, tool_jwk) do
    {_kty, fields} = JOSE.JWK.to_map(tool_jwk)
    jws = JOSE.JWS.from_map(%{"typ" => "JWT", "alg" => "RS256", "kid" => fields["kid"]})
    jwt = JOSE.JWT.from_map(claims)

    {_meta, token} =
      tool_jwk
      |> JOSE.JWT.sign(jws, jwt)
      |> JOSE.JWS.compact()

    token
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
