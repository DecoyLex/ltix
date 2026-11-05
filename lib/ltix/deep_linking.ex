defmodule Ltix.DeepLinking do
  @moduledoc """
  Put content items into a signed response JWT for the platform.

  When the platform sends an `LtiDeepLinkingRequest` launch, your tool
  presents a selection UI and calls `build_response/3` with the chosen
  items. Your tool then sends the response JWT back to the platform's return URL in a POST request.

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

  ## Extending

  Plugins add content item types with `Ltix.DeepLinking.ContentItemType`.
  They add properties to content items and Deep Linking line items with
  `Ltix.Property`. They add claims to the response with
  `Ltix.DeepLinking.Response` steps.
  """

  @behaviour Ltix.Plugin

  alias Ltix.DeepLinking.ContentItem
  alias Ltix.DeepLinking.ContentItemType
  alias Ltix.DeepLinking.LineItem
  alias Ltix.DeepLinking.Response
  alias Ltix.DeepLinking.Settings

  alias Ltix.Deployment
  alias Ltix.Errors
  alias Ltix.JWT.Token
  alias Ltix.Launch
  alias Ltix.Options
  alias Ltix.Plugin
  alias Ltix.PluginSet
  alias Ltix.Registerable
  alias Ltix.Registration
  alias Ltix.Step

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

  # [DL, Deep linking settings](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#deep-linking-settings)
  @presentation_targets ["embed", "iframe", "window"]

  @message_fields [
    message: Zoi.string(description: "A message the platform shows the user."),
    log: Zoi.string(description: "A message the platform logs."),
    error_message:
      Zoi.string(
        description:
          "An error message the platform shows the user, such as when your tool couldn't create the content."
      ),
    error_log: Zoi.string(description: "An error message the platform logs."),
    storage_adapter: Zoi.module(description: "The storage adapter that signs the response."),
    storage_adapter_options:
      Zoi.keyword(Zoi.any(),
        description: "Options passed to the storage adapter's signing callbacks."
      )
      |> Zoi.default([])
  ]

  @launch_schema Zoi.keyword(
                   @message_fields ++
                     [
                       plugins:
                         Zoi.list(Zoi.any(),
                           description:
                             "The plugins for this call, each as `MyPlugin` or `{MyPlugin, opts}`. Defaults to the launch's plugins."
                         )
                     ],
                   unrecognized_keys: :error
                 )

  @registration_schema Zoi.keyword(
                         [
                           settings:
                             Zoi.struct(Settings,
                               description:
                                 "The Deep Linking settings of the Deep Linking request, saved from `launch.claims.deep_linking_settings`."
                             )
                             |> Zoi.required(),
                           deployment:
                             Zoi.nullable(
                               Zoi.any(
                                 description:
                                   "The deployment of the Deep Linking request, as a struct implementing `Ltix.Deployable` or a deployment ID. Pass `nil` for a request without a deployment ID."
                               )
                             )
                             |> Zoi.required()
                         ] ++
                           @message_fields ++
                           [
                             plugins:
                               Zoi.list(Zoi.any(),
                                 description:
                                   "The plugins for this call, each as `MyPlugin` or `{MyPlugin, opts}`. Defaults to the configured plugins."
                               )
                           ],
                         unrecognized_keys: :error
                       )

  @impl Ltix.Plugin
  def plugin(_opts) do
    plugin =
      Plugin.new(name: "LTI Deep Linking 2.0", version: @version)
      |> Plugin.add(Ltix.DeepLinkingRequest)
      |> Plugin.add(Response)
      |> Plugin.add(ContentItemType)
      |> Plugin.add(LineItem)
      |> Plugin.add(Settings)

    Enum.reduce(@content_item_types, plugin, &Plugin.add(&2, &1))
  end

  @doc """
  Builds and signs a Deep Linking response with the content items the user
  chose.

  Takes the launch of a Deep Linking request, or a registration with the
  request's saved Deep Linking settings and deployment, and a list of content
  items. Returns an `Ltix.DeepLinking.Response` with the signed `jwt` and the
  platform's `return_url`. The JWT expires 5 minutes after signing.

  ## From a launch

  ```elixir
  {:ok, response} = Ltix.DeepLinking.build_response(launch, [link], message: "Added Quiz 7")
  ```

  ## From a registration

  Save `launch.claims.deep_linking_settings` when the Deep Linking request
  arrives, and pass it in `:settings` with the request's deployment. The
  registration is an `Ltix.Registration`, or your own struct that implements
  `Ltix.Registerable`.

  ```elixir
  {:ok, response} =
    Ltix.DeepLinking.build_response(registration, [link],
      settings: settings,
      deployment: deployment
    )
  ```

  ## Options

  When you [configure](`m:Ltix#module-configuration`) an option, the configured
  value is its default.

  ### From a launch

  #{Zoi.describe(@launch_schema)}

  ### From a registration

  #{Zoi.describe(@registration_schema)}

  ## Errors

    * `Ltix.Errors.Invalid.InvalidMessageType` - the launch isn't a Deep
      Linking request
    * `Ltix.Errors.Invalid.InvalidField` - the `:deployment` ID is invalid
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
    * `Ltix.Errors.Unknown.StorageError` - the storage adapter doesn't
      implement `c:Ltix.StorageAdapter.key_id/2` or
      `c:Ltix.StorageAdapter.sign/4`, or one of them fails
    * an error from a plugin's `Ltix.DeepLinking.Response` step

  An error about one item has the item's position in `items` as its
  `index`. Unknown or invalid options, a registration that doesn't implement
  `Ltix.Registerable`, and a `:deployment` that doesn't implement
  `Ltix.Deployable` raise `ArgumentError`.

  ## Canceling

  When the user cancels, return no content items.

  ```elixir
  {:ok, response} = Ltix.DeepLinking.build_response(launch, [], message: "Nothing was added")
  ```
  """
  @spec build_response(Launch.t() | Registerable.t(), list(), keyword()) ::
          {:ok, Response.t()} | {:error, Exception.t()}
  def build_response(launch_or_registerable, items \\ [], opts \\ [])

  def build_response(%Launch{} = launch, items, opts) do
    opts = Options.parse!(opts, @launch_schema)
    {enabled, opts} = Keyword.pop(opts, :plugins, launch.plugins)

    measure(items, enabled, opts, fn plugins, opts ->
      with :ok <- require_deep_linking_request(launch),
           {:ok, plugins} <- plugins do
        response = %Response{
          registration: launch.source_registration,
          deployment: launch.source_deployment,
          settings: launch.claims.deep_linking_settings,
          plugins: plugins
        }

        build(response, launch.registration, launch.deployment, items, opts)
      end
    end)
  end

  def build_response(registerable, items, opts) do
    opts = Options.parse!(opts, @registration_schema)
    {enabled, opts} = Keyword.pop(opts, :plugins)
    {settings, opts} = Keyword.pop!(opts, :settings)
    {deployable, opts} = Keyword.pop!(opts, :deployment)

    measure(items, enabled, opts, fn plugins, opts ->
      with {:ok, registration} <- Registration.from_source!(registerable),
           {:ok, deployment} <- Deployment.from_source_or_id(deployable),
           {:ok, plugins} <- plugins do
        response = %Response{
          registration: registerable,
          deployment: deployable,
          settings: settings,
          plugins: plugins
        }

        build(response, registration, deployment, items, opts)
      end
    end)
  end

  @doc """
  Same as `build_response/3` but raises on error.

  ## Examples

  ```elixir
  response = Ltix.DeepLinking.build_response!(launch, [link], message: "Selected 1 item")
  ```
  """
  @spec build_response!(Launch.t() | Registerable.t(), list(), keyword()) :: Response.t()
  def build_response!(launch_or_registerable, items \\ [], opts \\ []) do
    case build_response(launch_or_registerable, items, opts) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end

  # Runs `build` in the telemetry span, with the resolved plugins and the
  # options with the storage adapter.
  defp measure(items, enabled, opts, build) do
    opts = Keyword.put(opts, :storage_adapter, Options.fetch_configured!(opts, :storage_adapter))
    plugins = PluginSet.resolve(enabled)

    metadata = %{
      item_count: if(is_list(items), do: length(items), else: 0),
      item_types: item_types(items, plugins)
    }

    :telemetry.span([:ltix, :deep_linking, :build_response], metadata, fn ->
      {build.(plugins, opts), metadata}
    end)
  end

  defp item_types(items, {:ok, plugins}) when is_list(items) do
    types = PluginSet.data(plugins, ContentItemType)
    for %module{} <- items, Map.has_key?(types, module), uniq: true, do: types[module]
  end

  defp item_types(_items, _plugins), do: []

  defp require_deep_linking_request(%Launch{claims: %{message_type: "LtiDeepLinkingRequest"}}),
    do: :ok

  defp require_deep_linking_request(%Launch{claims: claims}),
    do: {:error, InvalidMessageType.exception(message_type: claims[:message_type])}

  # Signs with the registration from before the steps run, which can change
  # the response's fields.
  defp build(response, registration, deployment, items, opts) do
    %Response{registration: registerable, settings: settings} = response

    with {:ok, items_json} <- content_items(items, response.plugins, settings),
         claims = build_jwt_claims(registration, deployment, settings, items_json, opts),
         response =
           Step.run(%{response | claims: claims, return_url: settings.deep_link_return_url}),
         :ok <- Errors.collect(response.errors),
         # [Sec §5.4](https://www.imsglobal.org/spec/security/v1p0/#message-signing)
         {:ok, jwt} <-
           Token.sign(response.claims, registerable,
             storage_adapter: Keyword.fetch!(opts, :storage_adapter),
             storage_adapter_options: Keyword.fetch!(opts, :storage_adapter_options)
           ) do
      {:ok, %{response | jwt: jwt}}
    end
  end

  # --- Content items ---

  # [DL, Content items](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#content-items)
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

  # [DL, Deep linking settings](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#deep-linking-settings)
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

  # [DL, Deep linking response message](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#deep-linking-response-message)
  # [Sec §5.2.2](https://www.imsglobal.org/spec/security/v1p0/#tool-jwt)
  defp build_jwt_claims(%Registration{} = registration, deployment, settings, items_json, opts) do
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

  defp deployment_id(nil), do: nil
  defp deployment_id(%Deployment{deployment_id: deployment_id}), do: deployment_id

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
