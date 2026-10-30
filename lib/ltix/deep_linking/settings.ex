defmodule Ltix.DeepLinking.Settings do
  @moduledoc """
  What the platform accepts in a Deep Linking response, from the Deep
  Linking settings claim.

  A Deep Linking launch has it in `launch.claims.deep_linking_settings`. A
  malformed one fails the launch. An optional field the platform leaves out is
  `nil`.

  ```elixir
  settings = launch.claims.deep_linking_settings
  render(conn, :picker,
    types: settings.accept_types,
    multiple: settings.accept_multiple
  )
  ```
  """

  # [DL, Deep linking settings](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#deep-linking-settings)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings",
    name: :deep_linking_settings,
    fields: [
      deep_link_return_url: Zoi.string(description: "Where your tool posts the response."),
      accept_types:
        Zoi.list(Zoi.string(),
          description:
            "The content item types the platform accepts, such as `[\"ltiResourceLink\", \"link\"]`."
        ),
      accept_presentation_document_targets:
        Zoi.list(Zoi.string(),
          description:
            "Where the platform can show content items, such as `[\"iframe\", \"window\"]`."
        ),
      accept_media_types:
        Zoi.string(
          description:
            "A comma-separated string of the media types the platform accepts for `file` content items."
        )
        |> Zoi.optional(),
      accept_multiple:
        Zoi.boolean(description: "Whether the response can have several content items.")
        |> Zoi.optional(),
      accept_line_item:
        Zoi.boolean(
          description: "Whether the platform creates line items for content items.",
          metadata: [json_key: "accept_lineitem"]
        )
        |> Zoi.optional(),
      auto_create:
        Zoi.boolean(
          description:
            "Whether the platform saves the content items without letting the user cancel."
        )
        |> Zoi.optional(),
      title: Zoi.string(description: "Default title for the content items.") |> Zoi.optional(),
      text: Zoi.string(description: "Default text for the content items.") |> Zoi.optional(),
      data:
        Zoi.any(
          description:
            "A value `Ltix.DeepLinking.build_response/3` returns to the platform unchanged."
        )
        |> Zoi.optional()
    ]

  @doc """
  Adds an anonymous property of Deep Linking settings to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
