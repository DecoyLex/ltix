defmodule Ltix.Claims.ActualUser do
  @moduledoc """
  The person acting in an impersonation launch, from the actual user claim. For
  example, an administrator can view a context as a student.

  Read it from `launch.claims.actual_user`. When the value is malformed, it's
  `nil` and the launch continues. The launch's other claims describe the
  user being viewed.
  """

  # [Core, Impersonation launch case](https://standards.1edtech.org/lti/specifications/core/lti-spec#impersonation-launch-case)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/actual_user",
    name: :actual_user,
    strict: false,
    fields: [
      id: Zoi.string(description: "The acting person's subject identifier."),
      roles:
        Zoi.list(Zoi.string(),
          description:
            "The acting person's role URIs in the context. Check them with `Ltix.Role`."
        )
        |> Zoi.optional(),
      name: Zoi.string(description: "The acting person's full name.") |> Zoi.optional(),
      given_name: Zoi.string(description: "The acting person's given name.") |> Zoi.optional(),
      family_name: Zoi.string(description: "The acting person's family name.") |> Zoi.optional(),
      middle_name: Zoi.string(description: "The acting person's middle name.") |> Zoi.optional(),
      email: Zoi.string(description: "The acting person's email address.") |> Zoi.optional(),
      picture:
        Zoi.string(description: "The URL of the acting person's picture.") |> Zoi.optional(),
      locale: Zoi.string(description: "The acting person's preferred locale.") |> Zoi.optional()
    ]

  @doc """
  Adds an anonymous property of the actual user claim to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
