defmodule Ltix.Claims.ResourceLink do
  @moduledoc """
  The LTI link the user followed into the tool, from the resource link claim.

  Read it from `launch.claims.resource_link`. Every resource link launch has
  one.
  """

  # [Core §5.3.5](https://www.imsglobal.org/spec/lti/v1p3/#resource-link-claim)
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
end
