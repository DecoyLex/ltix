defmodule Ltix.DeepLinking.ContentItem.File do
  @moduledoc """
  A file content item for Deep Linking responses.

  File URLs are short-lived. The platform downloads the file shortly
  after receiving the response, so the URL only needs to remain valid
  for a few minutes.

  ## Examples

  ```elixir
  iex> {:ok, file} = Ltix.DeepLinking.ContentItem.File.new(
  ...>   url: "https://example.com/syllabus.pdf",
  ...>   media_type: "application/pdf"
  ...> )
  iex> file.media_type
  "application/pdf"

  iex> {:error, error} = Ltix.DeepLinking.ContentItem.File.new([])
  iex> Exception.message(error)
  "Ltix.DeepLinking.ContentItem.File field :url is required"
  ```
  """

  alias Ltix.DeepLinking.Settings
  alias Ltix.Errors.Invalid.MediaTypeNotAccepted

  # [DL, File](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#file)
  use Ltix.DeepLinking.ContentItemType,
    type: "file",
    fields: [
      url: Zoi.string(description: "URL to download the file."),
      title: title(),
      text: text(),
      icon: icon(),
      thumbnail: thumbnail(),
      media_type:
        Zoi.string(description: "Media type of the file, such as `\"application/pdf\"`.")
        |> Zoi.optional(),
      expires_at: Zoi.datetime(description: "When the download URL expires.") |> Zoi.optional()
    ]

  # `accept_media_types` only applies to files.
  # [DL, Deep linking settings](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#deep-linking-settings)
  @impl Ltix.DeepLinking.ContentItemType
  def check(%__MODULE__{media_type: media_type}, %Settings{accept_media_types: accepted}) do
    if accepted?(media_type, accepted) do
      :ok
    else
      {:error,
       MediaTypeNotAccepted.exception(
         media_type: media_type,
         accept_media_types: accepted
       )}
    end
  end

  # Whether `accepted`, a comma-separated list of media types, includes
  # `media_type`. An accepted media type matches exactly, as `type/*`, or as
  # `*/*`, ignoring case and parameters such as `charset`. Either one being
  # `nil` passes.
  defp accepted?(nil, _accepted), do: true
  defp accepted?(_media_type, nil), do: true

  # [RFC 7231 §5.3.2](https://www.rfc-editor.org/rfc/rfc7231#section-5.3.2)
  defp accepted?(media_type, accepted) do
    [type | _subtype] = essence = essence(media_type)

    accepted
    |> String.split(",")
    |> Enum.map(&essence/1)
    |> Enum.any?(&(&1 in [essence, [type, "*"], ["*", "*"]]))
  end

  # The lowercase type and subtype, without parameters.
  defp essence(media_type) do
    [essence | _parameters] = String.split(media_type, ";")

    essence
    |> String.trim()
    |> String.downcase()
    |> String.split("/", parts: 2)
  end

  @doc """
  Adds an anonymous property of `file` content items to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
