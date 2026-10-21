defmodule Ltix.Claims.LIS do
  @moduledoc """
  IDs for the user and the course in the institution's student information
  system, from the Learning Information Services (LIS) claim.

  Read it from `launch.claims.lis`. When the value is malformed, it's `nil` and
  the launch continues.
  """

  # [Core §5.4.5](https://www.imsglobal.org/spec/lti/v1p3/#learning-information-services-lis-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/lis",
    name: :lis,
    strict: false,
    fields: [
      person_source_id:
        Zoi.string(
          description: "The user's ID, from `person_sourcedid`.",
          metadata: [json_key: "person_sourcedid"]
        )
        |> Zoi.optional(),
      course_offering_source_id:
        Zoi.string(
          description: "The course offering's ID, from `course_offering_sourcedid`.",
          metadata: [json_key: "course_offering_sourcedid"]
        )
        |> Zoi.optional(),
      course_section_source_id:
        Zoi.string(
          description: "The course section's ID, from `course_section_sourcedid`.",
          metadata: [json_key: "course_section_sourcedid"]
        )
        |> Zoi.optional()
    ]

  @doc """
  Adds an anonymous property of the LIS claim to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
