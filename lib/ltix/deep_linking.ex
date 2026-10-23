defmodule Ltix.DeepLinking do
  @moduledoc """
  Put content items into a signed response JWT for the platform.

  When the platform sends an `LtiDeepLinkingRequest` launch, your tool
  presents a selection UI and calls `build_response/3` with the chosen
  items. The response JWT is then POSTed back to the platform's return URL.

  Content items are built with these modules.

    * `Ltix.DeepLinking.ContentItem.LTIResourceLink` - an LTI activity
      the platform will link to
    * `Ltix.DeepLinking.ContentItem.Link` - an external URL
    * `Ltix.DeepLinking.ContentItem.File` - a downloadable file
    * `Ltix.DeepLinking.ContentItem.HTMLFragment` - inline HTML to embed
    * `Ltix.DeepLinking.ContentItem.Image` - an image for direct rendering

  See the [Deep Linking](deep-linking.md) guide for the full workflow
  and [Building Content Items](cookbooks/building-content-items.md) for
  recipes.
  """

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.Response

  alias Ltix.LaunchContext
  alias Ltix.Options
  alias Ltix.Records
  alias Ltix.StorageAdapter

  alias Ltix.Errors.Invalid.ContentItemsExceedLimit
  alias Ltix.Errors.Invalid.ContentItemTypeNotAccepted
  alias Ltix.Errors.Invalid.InvalidContentItem
  alias Ltix.Errors.Invalid.InvalidMessageType
  alias Ltix.Errors.Invalid.LineItemNotAccepted
  alias Ltix.Errors.Invalid.MediaTypeNotAccepted
  alias Ltix.Errors.Invalid.PresentationTargetNotAccepted

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @dl "https://purl.imsglobal.org/spec/lti-dl/claim/"

  # [DL §3.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#link)
  # [DL §3.2](https://www.imsglobal.org/spec/lti-dl/v2p0/#lti-resource-link)
  @presentable_types ["link", "ltiResourceLink"]
  @presentation_targets ["embed", "iframe", "window"]

  @options_schema Zoi.keyword(
                    [
                      message: Zoi.string(),
                      log: Zoi.string(),
                      error_message: Zoi.string(),
                      error_log: Zoi.string(),
                      storage_adapter: Zoi.module(),
                      storage_adapter_options: Zoi.keyword(Zoi.any()) |> Zoi.default([])
                    ],
                    unrecognized_keys: :error
                  )

  @doc """
  Build a signed Deep Linking response JWT.

  Takes a `LaunchContext` from an `LtiDeepLinkingRequest` launch, a list of
  content items, and optional message/log fields. Returns a `Response` with
  the signed JWT and the platform's return URL.

  ## Options

    * `:message` - user-facing message to show on return
    * `:log` - log message for the platform
    * `:error_message` - user-facing error message
    * `:error_log` - error log message for the platform
    * `:storage_adapter` - module implementing `Ltix.StorageAdapter`, which
      signs the response (defaults to application config)
    * `:storage_adapter_options` - options passed to the storage adapter's
      signing callbacks (defaults to `[]`)

  ## Errors

    * `Ltix.Errors.Invalid.InvalidMessageType` - context is not a deep
      linking launch
    * `Ltix.Errors.Invalid.InvalidContentItem` - an item is not a content
      item, has no `"type"` or one that is not a string, or `items` is not a
      list
    * `Ltix.Errors.Invalid.ContentItemTypeNotAccepted` - item type not
      in `accept_types`
    * `Ltix.Errors.Invalid.ContentItemsExceedLimit` - multiple items
      when `accept_multiple` is `false`
    * `Ltix.Errors.Invalid.LineItemNotAccepted` - line item present
      when `accept_line_item` is `false`
    * `Ltix.Errors.Invalid.PresentationTargetNotAccepted` - an item is
      presented in an `iframe`, `window`, or `embed` that is not in
      `accept_presentation_document_targets`
    * `Ltix.Errors.Invalid.MediaTypeNotAccepted` - a file's `media_type`
      does not match `accept_media_types`

  Errors about one item include its `index` in `items`. Several failures at once
  are grouped in `Ltix.Errors.Invalid`. Unknown or invalid options raise
  `Ltix.Errors.Invalid.InvalidOption`.

  ## Examples

      {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
        url: "https://tool.example.com/activity/123",
        title: "Quiz 1"
      )

      {:ok, response} = Ltix.DeepLinking.build_response(context, [link],
        message: "Selected 1 item"
      )

      # response.jwt is the signed JWT to POST to response.return_url

  See the [Deep Linking](deep-linking.md) guide for the full workflow.
  """
  @spec build_response(LaunchContext.t(), list(), keyword()) ::
          {:ok, Response.t()} | {:error, Exception.t()}
  def build_response(context, items \\ [], opts \\ []) do
    opts = Options.parse!(opts, @options_schema)
    storage_adapter = Options.fetch_configured!(opts, :storage_adapter)
    serialized = serialize_items(items)

    metadata = %{
      item_count: if(is_list(items), do: length(items), else: 0),
      item_types: for({:ok, %{"type" => type}} <- serialized, uniq: true, do: type)
    }

    :telemetry.span([:ltix, :deep_linking, :build_response], metadata, fn ->
      {build(context, serialized, storage_adapter, opts), metadata}
    end)
  end

  @doc """
  Same as `build_response/3` but raises on error.

  ## Examples

      response = Ltix.DeepLinking.build_response!(context, [link], message: "Selected 1 item")
  """
  @spec build_response!(LaunchContext.t(), list(), keyword()) :: Response.t()
  def build_response!(context, items \\ [], opts \\ []) do
    case build_response(context, items, opts) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end

  defp build(
         %LaunchContext{claims: %{message_type: "LtiDeepLinkingRequest"}} = context,
         serialized,
         storage_adapter,
         opts
       ) do
    settings = context.claims.deep_linking_settings

    with {:ok, registration} <- Records.convert!(context.registration, :registration),
         {:ok, deployment} <- Records.convert!(context.deployment, :deployment),
         {:ok, items_json} <- collect_items(serialized),
         :ok <- validate_items(items_json, settings),
         claims = build_jwt_claims(registration, deployment, settings, items_json, opts),
         # [Sec §5.2.2](https://www.imsglobal.org/spec/security/v1p0/#tool-originating-messages)
         {:ok, jwt} <-
           StorageAdapter.sign_jwt(
             storage_adapter,
             context.registration,
             claims,
             Keyword.fetch!(opts, :storage_adapter_options)
           ) do
      {:ok, %Response{jwt: jwt, return_url: settings.deep_link_return_url}}
    end
  end

  defp build(%LaunchContext{claims: %{message_type: mt}}, _serialized, _storage_adapter, _opts) do
    {:error, InvalidMessageType.exception(message_type: mt)}
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
    InvalidContentItem.exception(index: index, value: value, reason: reason)
  end

  defp collect_items(serialized) do
    case for({:error, error} <- serialized, do: error) do
      [] -> {:ok, for({:ok, json} <- serialized, do: json)}
      errors -> {:error, Ltix.Errors.combine(errors)}
    end
  end

  # --- Validation ---

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  defp validate_items(items, settings) do
    item_errors =
      items
      |> Enum.with_index()
      |> Enum.flat_map(fn indexed ->
        type_not_accepted(indexed, settings.accept_types) ++
          line_item_not_accepted(indexed, settings.accept_line_item) ++
          presentation_not_accepted(indexed, settings.accept_presentation_document_targets) ++
          media_type_not_accepted(indexed, settings.accept_media_types)
      end)

    case item_errors ++ exceeds_limit(items, settings.accept_multiple) do
      [] -> :ok
      errors -> {:error, Ltix.Errors.combine(errors)}
    end
  end

  defp type_not_accepted({%{"type" => type}, index}, accept_types) do
    if type in accept_types do
      []
    else
      [
        ContentItemTypeNotAccepted.exception(index: index, type: type, accept_types: accept_types)
      ]
    end
  end

  defp exceeds_limit(items, false = _accept_multiple) when length(items) > 1 do
    [ContentItemsExceedLimit.exception(count: length(items))]
  end

  defp exceeds_limit(_items, _accept_multiple), do: []

  defp line_item_not_accepted(
         {%{"type" => "ltiResourceLink", "lineItem" => _}, index},
         false = _accept_line_item
       ) do
    [LineItemNotAccepted.exception(index: index)]
  end

  defp line_item_not_accepted(_indexed_item, _accept_line_item), do: []

  defp presentation_not_accepted(_indexed_item, nil = _accepted_targets), do: []

  defp presentation_not_accepted({%{"type" => type} = item, index}, accepted_targets)
       when type in @presentable_types do
    for target <- @presentation_targets,
        Map.has_key?(item, target),
        target not in accepted_targets do
      PresentationTargetNotAccepted.exception(
        index: index,
        target: target,
        accept_presentation_document_targets: accepted_targets
      )
    end
  end

  defp presentation_not_accepted(_indexed_item, _accepted_targets), do: []

  defp media_type_not_accepted(
         {%{"type" => "file", "mediaType" => media_type}, index},
         accept_media_types
       )
       when is_binary(media_type) and is_binary(accept_media_types) do
    if media_type_accepted?(media_type, accept_media_types) do
      []
    else
      [
        MediaTypeNotAccepted.exception(
          index: index,
          media_type: media_type,
          accept_media_types: accept_media_types
        )
      ]
    end
  end

  defp media_type_not_accepted(_indexed_item, _accept_media_types), do: []

  # [RFC 7231 §5.3.2](https://www.rfc-editor.org/rfc/rfc7231#section-5.3.2)
  defp media_type_accepted?(media_type, accept_media_types) do
    [type | _subtype] = essence = media_type_essence(media_type)

    accept_media_types
    |> String.split(",")
    |> Enum.map(&media_type_essence/1)
    |> Enum.any?(&(&1 in [essence, [type, "*"], ["*", "*"]]))
  end

  # The lowercase type and subtype, without parameters.
  defp media_type_essence(media_type) do
    [essence | _parameters] = String.split(media_type, ";")

    essence
    |> String.trim()
    |> String.downcase()
    |> String.split("/", parts: 2)
  end

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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
