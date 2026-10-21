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

  Plugins add content item types with `Ltix.DeepLinking.ContentItemType`.

  `Ltix.DeepLinking` is also the default plugin for Deep Linking 2.0. It
  provides the `Ltix.DeepLinkingRequest` message type,
  `Ltix.DeepLinking.ContentItemType`, and the five content item types, and
  declares the `Ltix.DeepLinking.Settings` claim.

  See the [Deep Linking](deep-linking.md) guide for the full workflow
  and [Building Content Items](cookbooks/building-content-items.md) for
  recipes.
  """

  @behaviour Ltix.Plugin

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItemType
  alias Ltix.DeepLinking.Response
  alias Ltix.DeepLinking.Settings

  alias Ltix.Errors
  alias Ltix.Launch
  alias Ltix.Options
  alias Ltix.Plugin
  alias Ltix.PluginSet
  alias Ltix.StorageAdapter

  alias Ltix.Errors.Invalid.ContentItemsExceedLimit
  alias Ltix.Errors.Invalid.ContentItemTypeNotAccepted
  alias Ltix.Errors.Invalid.InvalidContentItem
  alias Ltix.Errors.Invalid.InvalidMessageType
  alias Ltix.Errors.Invalid.PresentationTargetNotAccepted

  @version Mix.Project.config()[:version]

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @dl "https://purl.imsglobal.org/spec/lti-dl/claim/"

  @content_item_types [
    ContentItem.LTIResourceLink,
    ContentItem.Link,
    ContentItem.File,
    ContentItem.HTMLFragment,
    ContentItem.Image
  ]

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  @presentation_targets ["embed", "iframe", "window"]

  @options_schema Zoi.keyword(
                    [
                      message: Zoi.string(),
                      log: Zoi.string(),
                      error_message: Zoi.string(),
                      error_log: Zoi.string(),
                      storage_adapter: Zoi.module(),
                      storage_adapter_options: Zoi.keyword(Zoi.any()) |> Zoi.default([]),
                      plugins: Zoi.list(Zoi.any())
                    ],
                    unrecognized_keys: :error
                  )

  @impl Ltix.Plugin
  def plugin(_opts) do
    plugin =
      Plugin.new(name: "LTI Deep Linking 2.0", version: @version)
      |> Plugin.add(Ltix.DeepLinkingRequest)
      |> Plugin.add(ContentItemType)
      |> Plugin.add(Settings)

    Enum.reduce(@content_item_types, plugin, &Plugin.add(&2, &1))
  end

  @doc """
  Build a signed Deep Linking response JWT.

  Takes an `Ltix.Launch` from an `LtiDeepLinkingRequest` launch, a list of
  content items, and optional message/log fields. Returns a `Response` with
  the signed JWT and the platform's return URL.

  Each content item is a struct of a content item type in the plugin set,
  such as `Ltix.DeepLinking.ContentItem.LTIResourceLink`. The response
  includes each property in the plugin set that a content item has an
  extension for.

  ## Options

    * `:message` - user-facing message to show on return
    * `:log` - log message for the platform
    * `:error_message` - user-facing error message
    * `:error_log` - error log message for the platform
    * `:storage_adapter` - module implementing `Ltix.StorageAdapter`, which
      signs the response (defaults to application config)
    * `:storage_adapter_options` - options passed to the storage adapter's
      signing callbacks (defaults to `[]`)
    * `:plugins` - the plugins for this call, each as `MyPlugin` or
      `{MyPlugin, opts}` (defaults to the launch's plugins)

  ## Errors

    * `Ltix.Errors.Invalid.InvalidMessageType` - the launch isn't a Deep
      Linking request
    * `Ltix.Errors.Invalid.InvalidContentItem` - an item isn't a content
      item struct, or `items` isn't a list
    * `Ltix.Errors.Invalid.ContentItemTypeNotAccepted` - an item's type
      isn't in `accept_types`
    * `Ltix.Errors.Invalid.ContentItemsExceedLimit` - there's more than one
      item when `accept_multiple` is `false`
    * `Ltix.Errors.Invalid.LineItemNotAccepted` - an LTI resource link has a
      line item when `accept_line_item` is `false`
    * `Ltix.Errors.Invalid.PresentationTargetNotAccepted` - an item's
      `iframe`, `window`, or `embed` isn't in
      `accept_presentation_document_targets`
    * `Ltix.Errors.Invalid.MediaTypeNotAccepted` - a file's `media_type`
      doesn't match `accept_media_types`
    * `Ltix.Errors.Unknown.InvalidPluginSet` - the plugins conflict

  Errors about one item include its `index` in `items`. Several failures at
  once are grouped in `Ltix.Errors.Invalid`. Unknown or invalid options raise
  `Ltix.Errors.Invalid.InvalidOption`.

  ## Examples

      {:ok, link} = Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
        url: "https://tool.example.com/activity/123",
        title: "Quiz 1"
      )

      {:ok, response} = Ltix.DeepLinking.build_response(launch, [link],
        message: "Selected 1 item"
      )

      # response.jwt is the signed JWT to POST to response.return_url

  See the [Deep Linking](deep-linking.md) guide for the full workflow.
  """
  @spec build_response(Launch.t(), list(), keyword()) ::
          {:ok, Response.t()} | {:error, Exception.t()}
  def build_response(launch, items \\ [], opts \\ []) do
    opts = Options.parse!(opts, @options_schema)
    storage_adapter = Options.fetch_configured!(opts, :storage_adapter)
    {enabled, opts} = Keyword.pop(opts, :plugins, launch.plugins)
    plugins = PluginSet.resolve(enabled)

    metadata = %{
      item_count: if(is_list(items), do: length(items), else: 0),
      item_types: item_types(items, plugins)
    }

    :telemetry.span([:ltix, :deep_linking, :build_response], metadata, fn ->
      {build(launch, items, plugins, storage_adapter, opts), metadata}
    end)
  end

  @doc """
  Same as `build_response/3` but raises on error.

  ## Examples

      response = Ltix.DeepLinking.build_response!(launch, [link], message: "Selected 1 item")
  """
  @spec build_response!(Launch.t(), list(), keyword()) :: Response.t()
  def build_response!(launch, items \\ [], opts \\ []) do
    case build_response(launch, items, opts) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end

  defp item_types(items, {:ok, plugins}) when is_list(items) do
    types = PluginSet.data(plugins, ContentItemType)
    for %module{} <- items, Map.has_key?(types, module), uniq: true, do: types[module]
  end

  defp item_types(_items, _plugins), do: []

  defp build(
         %Launch{claims: %{message_type: "LtiDeepLinkingRequest"}} = launch,
         items,
         plugins,
         storage_adapter,
         opts
       ) do
    settings = launch.claims.deep_linking_settings

    with {:ok, plugins} <- plugins,
         {:ok, items_json} <- content_items(items, plugins, settings),
         claims =
           build_jwt_claims(launch.registration, launch.deployment, settings, items_json, opts),
         # [Sec §5.2.2](https://www.imsglobal.org/spec/security/v1p0/#tool-originating-messages)
         {:ok, jwt} <-
           StorageAdapter.sign_jwt(
             storage_adapter,
             launch.source_registration,
             claims,
             Keyword.fetch!(opts, :storage_adapter_options)
           ) do
      {:ok, %Response{jwt: jwt, return_url: settings.deep_link_return_url}}
    end
  end

  defp build(%Launch{claims: claims}, _items, _plugins, _storage_adapter, _opts) do
    {:error, InvalidMessageType.exception(message_type: claims[:message_type])}
  end

  # --- Content items ---

  # [DL §4.5.6](https://www.imsglobal.org/spec/lti-dl/v2p0/#content-items)
  defp content_items(items, plugins, settings) when is_list(items) do
    types = PluginSet.data(plugins, ContentItemType)
    indexed = Enum.with_index(items)

    with [] <-
           for({item, index} <- indexed, !declared?(item, types), do: undeclared(item, index)),
         {json, errors} =
           Enum.unzip(
             for {item, index} <- indexed, do: serialize(item, index, types, plugins, settings)
           ),
         [] <- Enum.concat(errors) ++ exceeds_limit(items, settings.accept_multiple) do
      {:ok, json}
    else
      errors -> {:error, Errors.combine(errors)}
    end
  end

  defp content_items(items, _plugins, _settings) do
    {:error, invalid_item(nil, items, "must be a list")}
  end

  defp declared?(%module{}, types), do: Map.has_key?(types, module)
  defp declared?(_item, _types), do: false

  defp undeclared(item, index),
    do: invalid_item(index, item, "is not a content item")

  defp invalid_item(index, value, reason) do
    InvalidContentItem.exception(index: index, value: value, reason: reason)
  end

  # Returns the content item's JSON and the errors of its checks.
  defp serialize(%module{} = item, index, types, plugins, settings) do
    type = types[module]
    json = Map.put(Ltix.Type.to_json(item, plugins), "type", type)

    errors =
      type_not_accepted(type, index, settings.accept_types) ++
        presentation_not_accepted(json, index, settings.accept_presentation_document_targets) ++
        check(item, index, settings)

    {json, errors}
  end

  # --- Checks ---

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  defp type_not_accepted(type, index, accept_types) do
    if type in accept_types do
      []
    else
      [
        ContentItemTypeNotAccepted.exception(index: index, type: type, accept_types: accept_types)
      ]
    end
  end

  defp presentation_not_accepted(_json, _index, nil = _accepted_targets), do: []

  defp presentation_not_accepted(json, index, accepted_targets) do
    for target <- @presentation_targets,
        Map.has_key?(json, target),
        target not in accepted_targets do
      PresentationTargetNotAccepted.exception(
        index: index,
        target: target,
        accept_presentation_document_targets: accepted_targets
      )
    end
  end

  defp check(%module{} = item, index, settings) do
    with true <- function_exported?(module, :check, 2),
         {:error, error} <- module.check(item, settings) do
      [put_index(error, index)]
    else
      _passed -> []
    end
  end

  defp put_index(%{index: nil} = error, index), do: %{error | index: index}
  defp put_index(error, _index), do: error

  defp exceeds_limit(items, false = _accept_multiple) when length(items) > 1 do
    [ContentItemsExceedLimit.exception(index: 1, count: length(items))]
  end

  defp exceeds_limit(_items, _accept_multiple), do: []

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
      (@lti <> "message_type") => "LtiDeepLinkingResponse",
      (@lti <> "version") => "1.3.0",
      (@dl <> "content_items") => items_json
    }
    |> maybe_put(@lti <> "deployment_id", deployment_id(deployment))
    |> maybe_put(@dl <> "data", settings.data)
    |> maybe_put(@dl <> "msg", Keyword.get(opts, :message))
    |> maybe_put(@dl <> "log", Keyword.get(opts, :log))
    |> maybe_put(@dl <> "errormsg", Keyword.get(opts, :error_message))
    |> maybe_put(@dl <> "errorlog", Keyword.get(opts, :error_log))
  end

  # A launch has no deployment when a plugin makes `deployment_id` optional.
  defp deployment_id(nil), do: nil
  defp deployment_id(deployment), do: deployment.deployment_id

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
