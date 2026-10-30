defmodule Ltix.Claims.Context do
  @moduledoc """
  The course, section, or group a launch is in, from the context claim.

  Read it from `launch.claims.context`. When the value is malformed, it's `nil`
  and the launch continues.
  """

  # [Core, Context claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#context-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/context",
    name: :context,
    strict: false,
    fields: [
      id: Zoi.string(description: "The context's ID, unique within the deployment."),
      label:
        Zoi.string(description: "The context's short name, such as a course code.")
        |> Zoi.optional(),
      title: Zoi.string(description: "The context's full name.") |> Zoi.optional(),
      type: Zoi.list(Zoi.string(), description: "The context's type URIs.") |> Zoi.optional()
    ]

  @doc """
  Adds an anonymous property of the context claim to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
