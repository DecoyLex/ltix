defmodule Ltix.Claims.ResourceLink do
  @moduledoc """
  The LTI link the user followed into the tool, from the resource link claim.

  Read it from `launch.claims.resource_link`. Every resource link launch has
  one.
  """

  # [Core, Resource link claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#resource-link-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/resource_link",
    name: :resource_link,
    fields: [
      id:
        Zoi.string(
          description:
            "The resource link's ID, unique within the deployment and the same in every launch from the link."
        )
        |> Zoi.min(1),
      title: Zoi.string(description: "The resource link's title.") |> Zoi.optional(),
      description:
        Zoi.string(description: "A description of the resource link.") |> Zoi.optional()
    ]

  @doc """
  Adds an anonymous property of the resource link claim to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
