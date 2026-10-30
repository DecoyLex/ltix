defmodule Ltix.DeepLinking.ContentItemType do
  @moduledoc """
  Declares a content item type.

  ```elixir
  defmodule MyLibrary.Poll do
    @moduledoc "A poll the platform shows to learners."

    use Ltix.DeepLinking.ContentItemType,
      type: "https://lms.example.com/poll",
      fields: [
        question: Zoi.string(description: "The question to ask."),
        title: title(),
        closes_at: Zoi.datetime(description: "When the poll closes.") |> Zoi.optional()
      ]
  end
  ```

  Build an item with `new/1` or `new!/1`, from its fields as a keyword list or
  map. Shared fields such as `title/1` come from
  `Ltix.DeepLinking.ContentItemType.Fields`.

  Override `new/1` to accept other input, and call `super/1` to build the item.

  Add the content item type to a plugin with `Ltix.Plugin.add/2`.

  ## Options

    * `:type` - the content item's `type` string, which
      `Ltix.DeepLinking.build_response/3` checks against `accept_types`
      (required)
    * `:fields` - the content item's fields, as a keyword list of Zoi schemas
      (required)

  ## JSON

  In a Deep Linking response, each field's JSON name is the camelCase form
  of its name, such as `mediaType` for `media_type`. Fields that are `nil`
  are left out. Give a field another JSON name with `json_key:` in its schema's
  metadata. Keys that nested schemas declare, such as `target_name` in
  `window/1`, are camelized too. Other keys, such as those of a free-form
  map, keep their names.

  ## Checks

  `Ltix.DeepLinking.build_response/3` checks each content item's `type`
  against the platform's `accept_types`, and its `window`, `iframe`, and
  `embed` against `accept_presentation_document_targets`. Implement
  `c:check/2` to check other settings.

  ## Properties

  Plugins add properties to content item types, as `Ltix.Property` describes.
  Pass a property to `new/1` by its name, and read it from `extensions`.

  ```elixir
  {:ok, link} =
    Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
      url: "https://tool.example.com/quizzes/7",
      weight: 2
    )

  link.extensions.weight
  #=> 2
  ```

  [Add a property to a content item type](writing-deep-linking-plugins.md#add-a-property-to-a-content-item-type)
  shows an example.

  ## Conflicts

  When two of a call's plugins declare the same `type`, the call returns
  `Ltix.Errors.Unknown.InvalidPluginSet`. It also returns it for each of the
  property conflicts `Ltix.Property.conflicts/2` lists on a content item type.
  """
  use Ltix.Provider, hook: [Ltix.DeepLinking.ContentItemType.Definition]

  alias Ltix.DeepLinking.Settings
  alias Ltix.PluginSet
  alias Ltix.PluginSet.Conflict

  @doc """
  Checks a content item against the platform's Deep Linking settings.

  Return `{:error, exception}` for a content item the platform doesn't
  accept. When your exception has an `:index` field set to `nil`, Ltix sets
  it to the item's position in the response.

  ```elixir
  # A poll only works in an iframe.
  @impl Ltix.DeepLinking.ContentItemType
  def check(_poll, %Ltix.DeepLinking.Settings{accept_presentation_document_targets: targets}) do
    if "iframe" in targets,
      do: :ok,
      else: {:error, MyLibrary.IframeRequired.exception(index: nil)}
  end
  ```
  """
  @callback check(item :: struct(), settings :: Settings.t()) :: :ok | {:error, Exception.t()}

  @optional_callbacks check: 2

  @doc """
  Returns a content item type's `type` string.

  ## Examples

  ```elixir
  iex> Ltix.DeepLinking.ContentItemType.type(Ltix.DeepLinking.ContentItem.LTIResourceLink)
  "ltiResourceLink"
  ```
  """
  @spec type(module()) :: String.t()
  def type(content_item_type) do
    metadata = Zoi.metadata(content_item_type.__ltix_type__(:schema))
    Keyword.fetch!(metadata, :content_item_type)
  end

  @doc """
  Returns a content item type's fields as a keyword list of Zoi schemas, in
  declaration order.

  ## Examples

  ```elixir
  iex> Keyword.keys(Ltix.DeepLinking.ContentItemType.fields(Ltix.DeepLinking.ContentItem.HTMLFragment))
  [:html, :title, :text]
  ```
  """
  @spec fields(module()) :: keyword(Zoi.schema())
  defdelegate fields(content_item_type), to: Ltix.Type

  # The data is the `type` string of each content item type in the plugin set,
  # keyed by its module.
  @impl Ltix.Provider
  def resolve(%PluginSet{} = plugins) do
    entries = PluginSet.entries(plugins, __MODULE__)

    conflicts =
      Conflict.duplicates(
        entries,
        & &1.opts[:type],
        &"both declare the content item type #{inspect(&1)}"
      )

    case conflicts do
      [] -> {:ok, Map.new(entries, &{&1.module, &1.opts[:type]})}
      conflicts -> {:error, conflicts}
    end
  end
end
