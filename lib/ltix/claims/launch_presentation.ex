defmodule Ltix.Claims.LaunchPresentation do
  @moduledoc """
  How the platform shows the tool, from the launch presentation claim.

  Read it from `launch.claims.launch_presentation`. When the value is malformed,
  it's `nil` and the launch continues.
  """

  # [Core, Launch presentation claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#launch-presentation-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/launch_presentation",
    name: :launch_presentation,
    strict: false,
    fields: [
      document_target:
        Zoi.string(
          description:
            "Where the tool is shown, usually `\"frame\"`, `\"iframe\"`, or `\"window\"`."
        )
        |> Zoi.optional(),
      height:
        Zoi.number(coerce: true, description: "The height of the frame or window, in pixels.")
        |> Zoi.optional(),
      width:
        Zoi.number(coerce: true, description: "The width of the frame or window, in pixels.")
        |> Zoi.optional(),
      return_url:
        Zoi.string(description: "Where to send the user when they're done.") |> Zoi.optional(),
      locale:
        Zoi.string(description: "The user's language and region, such as `\"en-US\"`.")
        |> Zoi.optional()
    ]

  @doc """
  Adds an anonymous property of the launch presentation claim to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
