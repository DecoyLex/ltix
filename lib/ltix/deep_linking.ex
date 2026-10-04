defmodule Ltix.DeepLinking do
  @moduledoc """
  Package content items into a signed response JWT for the platform.

  When the platform sends an `LtiDeepLinkingRequest` launch, your tool
  presents a selection UI and calls `build_response/3` with the chosen
  items. The response JWT is then POSTed back to the platform's return URL.

  Content items are built with these modules:

    * `Ltix.DeepLinking.ContentItem.LTIResourceLink` — an LTI activity
      the platform will link to
    * `Ltix.DeepLinking.ContentItem.Link` — an external URL
    * `Ltix.DeepLinking.ContentItem.File` — a downloadable file
    * `Ltix.DeepLinking.ContentItem.HTMLFragment` — inline HTML to embed
    * `Ltix.DeepLinking.ContentItem.Image` — an image for direct rendering

  See the [Deep Linking](deep-linking.md) guide for the full workflow
  and [Building Content Items](cookbooks/building-content-items.md) for
  recipes.
  """

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.Response

  alias Ltix.Deployable
  alias Ltix.LaunchContext
  alias Ltix.Options
  alias Ltix.Registerable

  alias Ltix.Errors.Invalid.ContentItemsExceedLimit
  alias Ltix.Errors.Invalid.ContentItemTypeNotAccepted
  alias Ltix.Errors.Invalid.InvalidContentItem
  alias Ltix.Errors.Invalid.InvalidMessageType
  alias Ltix.Errors.Invalid.LineItemNotAccepted

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @dl "https://purl.imsglobal.org/spec/lti-dl/claim/"

  @options_schema Zoi.keyword(
                    [
                      message: Zoi.string(),
                      log: Zoi.string(),
                      error_message: Zoi.string(),
                      error_log: Zoi.string()
                    ],
                    unrecognized_keys: :error
                  )

  @doc """
  Build a signed Deep Linking response JWT.

  Takes a `LaunchContext` from an `LtiDeepLinkingRequest` launch, a list of
  content items, and optional message/log fields. Returns a `Response` with
  the signed JWT and the platform's return URL.

  ## Options

    * `:message` — user-facing message to show on return
    * `:log` — log message for the platform
    * `:error_message` — user-facing error message
    * `:error_log` — error log message for the platform

  ## Errors

    * `Ltix.Errors.Invalid.InvalidMessageType` — context is not a deep
      linking launch
    * `Ltix.Errors.Invalid.InvalidContentItem` — an item is not a content
      item, has no `"type"` or one that is not a string, or `items` is not a
      list
    * `Ltix.Errors.Invalid.ContentItemTypeNotAccepted` — item type not
      in `accept_types`
    * `Ltix.Errors.Invalid.ContentItemsExceedLimit` — multiple items
      when `accept_multiple` is `false`
    * `Ltix.Errors.Invalid.LineItemNotAccepted` — line item present
      when `accept_line_item` is `false`

  Unknown or invalid options raise `Ltix.Errors.Invalid.InvalidOption`.

  ## Examples

      {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
        url: "https://tool.example.com/activity/123",
        title: "Quiz 1"
      )

      {:ok, response} = Ltix.DeepLinking.build_response(context, [link],
        message: "Selected 1 item"
      )

      # response.jwt — signed JWT to POST to response.return_url

  See the [Deep Linking](deep-linking.md) guide for the full workflow.
  """
  @spec build_response(LaunchContext.t(), list(), keyword()) ::
          {:ok, Response.t()} | {:error, Exception.t()}
  def build_response(context, items \\ [], opts \\ []) do
    opts = Options.parse!(opts, @options_schema)
    serialized = serialize_items(items)

    metadata = %{
      item_count: if(is_list(items), do: length(items), else: 0),
      item_types: for({:ok, %{"type" => type}} <- serialized, uniq: true, do: type)
    }

    :telemetry.span([:ltix, :deep_linking, :build_response], metadata, fn ->
      {build(context, serialized, opts), metadata}
    end)
  end

  defp build(
         %LaunchContext{claims: %{message_type: "LtiDeepLinkingRequest"}} = context,
         serialized,
         opts
       ) do
    settings = context.claims.deep_linking_settings

    with {:ok, registration} <- Registerable.to_registration(context.registration),
         {:ok, deployment} <- Deployable.to_deployment(context.deployment),
         {:ok, items_json} <- collect_items(serialized),
         :ok <- validate_item_types(items_json, settings.accept_types),
         :ok <- validate_multiplicity(items_json, settings.accept_multiple),
         :ok <- validate_line_items(items_json, settings.accept_line_item) do
      claims = build_jwt_claims(registration, deployment, settings, items_json, opts)
      jwt = sign_jwt(claims, registration.tool_jwk)
      {:ok, %Response{jwt: jwt, return_url: settings.deep_link_return_url}}
    end
  end

  defp build(%LaunchContext{claims: %{message_type: mt}}, _serialized, _opts) do
    {:error, InvalidMessageType.exception(message_type: mt, spec_ref: "DL §4.5")}
  end

  # --- Serialization ---

  # [DL §4.5.6](https://www.imsglobal.org/spec/lti-dl/v2p0/#content-items)
  defp serialize_items(items) when is_list(items) do
    items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} -> serialize_item(item, index) end)
  end

  defp serialize_items(items) do
    [{:error, invalid_item(nil, items, "must be a list")}]
  end

  defp serialize_item(item, index) do
    case ContentItem.impl_for(item) do
      nil -> {:error, invalid_item(index, item, "is not a content item")}
      impl -> check_type(impl.to_map(item), item, index)
    end
  end

  # [DL §3.7](https://www.imsglobal.org/spec/lti-dl/v2p0/#defining-new-types)
  defp check_type(%{"type" => type} = json, _item, _index) when is_binary(type), do: {:ok, json}

  defp check_type(%{"type" => type}, _item, index) do
    {:error, invalid_item(index, type, ~s(has a "type" that is not a string))}
  end

  defp check_type(_json, item, index),
    do: {:error, invalid_item(index, item, ~s(has no "type"))}

  defp invalid_item(index, value, reason) do
    InvalidContentItem.exception(
      index: index,
      value: value,
      reason: reason,
      spec_ref: "DL §4.5.6"
    )
  end

  defp collect_items(serialized) do
    case for({:error, error} <- serialized, do: error) do
      [] -> {:ok, for({:ok, json} <- serialized, do: json)}
      errors -> {:error, Ltix.Errors.combine(errors)}
    end
  end

  # --- Validation ---

  defp validate_item_types(items, accept_types) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      type = item["type"]

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

  defp validate_line_items(items, accept_line_item) when accept_line_item == false do
    has_line_item? =
      Enum.any?(items, fn
        %{"type" => "ltiResourceLink", "lineItem" => _} -> true
        _ -> false
      end)

    if has_line_item? do
      {:error, LineItemNotAccepted.exception(spec_ref: "DL §4.4.1")}
    else
      :ok
    end
  end

  defp validate_line_items(_items, _accept_line_item), do: :ok

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
    |> maybe_put(@dl <> "msg", Keyword.get(opts, :message))
    |> maybe_put(@dl <> "log", Keyword.get(opts, :log))
    |> maybe_put(@dl <> "errormsg", Keyword.get(opts, :error_message))
    |> maybe_put(@dl <> "errorlog", Keyword.get(opts, :error_log))
  end

  # [Sec §5.2.2](https://www.imsglobal.org/spec/security/v1p0/#tool-originating-messages)
  defp sign_jwt(claims, tool_jwk) do
    jose_jwk = Ltix.JWK.to_jose(tool_jwk)
    {_kty, fields} = JOSE.JWK.to_map(jose_jwk)
    jws = JOSE.JWS.from_map(%{"typ" => "JWT", "alg" => "RS256", "kid" => fields["kid"]})
    jwt = JOSE.JWT.from_map(claims)

    {_meta, token} =
      jose_jwk
      |> JOSE.JWT.sign(jws, jwt)
      |> JOSE.JWS.compact()

    token
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
