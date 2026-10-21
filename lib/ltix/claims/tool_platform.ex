defmodule Ltix.Claims.ToolPlatform do
  @moduledoc """
  The platform installation that sent the launch, such as a university's Canvas,
  from the platform instance claim.

  Read it from `launch.claims.tool_platform`. When the value is malformed, it's
  `nil` and the launch continues.
  """

  # [Core §5.4.2](https://www.imsglobal.org/spec/lti/v1p3/#platform-instance-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/tool_platform",
    name: :tool_platform,
    strict: false,
    fields: [
      guid: Zoi.string(description: "The platform installation's ID, unique within the issuer."),
      name: Zoi.string(description: "The platform installation's name.") |> Zoi.optional(),
      contact_email:
        Zoi.string(description: "The administrative contact's email address.")
        |> Zoi.optional(),
      description:
        Zoi.string(description: "A description of the platform installation.")
        |> Zoi.optional(),
      url: Zoi.string(description: "The platform installation's home page.") |> Zoi.optional(),
      product_family_code:
        Zoi.string(description: "The platform's product, such as `\"canvas\"`.")
        |> Zoi.optional(),
      version: Zoi.string(description: "The platform's version.") |> Zoi.optional()
    ]
end
