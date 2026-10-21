defmodule Ltix.Claims.Organization do
  @moduledoc """
  The institution that supports the context, such as a university, from the
  organization claim.

  Read it from `launch.claims.organization`. When the value is malformed, it's
  `nil` and the launch continues.
  """

  # [Core 1.3.0 §5.4.2](https://standards.1edtech.org/lti/specifications/core/lti-spec#organization-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/organization",
    name: :organization,
    strict: false,
    fields: [
      id: Zoi.string(description: "The organization's ID, which several deployments can share."),
      type:
        Zoi.string(
          description: "The kind of organization, such as `\"institution\"` or `\"school\"`."
        )
        |> Zoi.optional(),
      name: Zoi.string(description: "The organization's name.") |> Zoi.optional(),
      description:
        Zoi.string(description: "A description of the organization.") |> Zoi.optional(),
      url: Zoi.string(description: "The organization's website.") |> Zoi.optional()
    ]
end
