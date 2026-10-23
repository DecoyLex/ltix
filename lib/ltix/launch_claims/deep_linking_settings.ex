defmodule Ltix.LaunchClaims.DeepLinkingSettings do
  @moduledoc """
  Platform preferences for a Deep Linking content selection.

  Sent by the platform in an `LtiDeepLinkingRequest` launch to specify
  what kinds of content items are accepted.

  ## Required fields

    * `:deep_link_return_url` - where the tool posts the response JWT
    * `:accept_types` - content item types the platform accepts
      (e.g., `["ltiResourceLink", "link"]`)
    * `:accept_presentation_document_targets` - how the content may be
      presented (e.g., `["iframe", "window"]`)

  ## Optional fields

    * `:accept_media_types` - comma-separated MIME types for `file` items
    * `:accept_multiple` - whether multiple items may be returned
    * `:accept_line_item` - whether the platform will create line items
    * `:auto_create` - whether the platform will auto-create resources
    * `:title` - suggested title for the content selection UI
    * `:text` - suggested description for the content selection UI
    * `:data` - opaque value the tool must return unchanged in the response

  See the [Deep Linking](deep-linking.md) guide for using these settings.
  """

  alias Ltix.LaunchClaims.ClaimHelpers

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  @struct_schema Zoi.struct(
                   __MODULE__,
                   %{
                     deep_link_return_url: Zoi.string(),
                     accept_types: Zoi.list(Zoi.string()),
                     accept_presentation_document_targets: Zoi.list(Zoi.string()),
                     accept_media_types: Zoi.string() |> ClaimHelpers.optional(),
                     accept_multiple: Zoi.boolean() |> ClaimHelpers.optional(),
                     accept_line_item: Zoi.boolean() |> ClaimHelpers.optional(),
                     auto_create: Zoi.boolean() |> ClaimHelpers.optional(),
                     title: Zoi.string() |> ClaimHelpers.optional(),
                     text: Zoi.string() |> ClaimHelpers.optional(),
                     data: Zoi.any() |> Zoi.nullish()
                   },
                   coerce: true
                 )

  @schema ClaimHelpers.rename_claims(@struct_schema, %{"accept_lineitem" => :accept_line_item})

  @doc false
  def schema, do: @schema

  @type t :: unquote(Zoi.type_spec(@struct_schema))
  @enforce_keys Zoi.Struct.enforce_keys(@struct_schema)
  defstruct Zoi.Struct.struct_fields(@struct_schema)

  @doc """
  Parse a deep linking settings claim from a JSON map.

  ## Examples

      iex> json = %{
      ...>   "deep_link_return_url" => "https://example.com/return",
      ...>   "accept_types" => ["link"],
      ...>   "accept_presentation_document_targets" => ["iframe"]
      ...> }
      iex> {:ok, settings} = Ltix.LaunchClaims.DeepLinkingSettings.from_json(json)
      iex> settings.deep_link_return_url
      "https://example.com/return"
      iex> settings.accept_types
      ["link"]
  """
  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) do
    ClaimHelpers.from_json(@schema, json, "deep_linking_settings")
  end
end
