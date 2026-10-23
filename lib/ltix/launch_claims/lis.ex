defmodule Ltix.LaunchClaims.LIS do
  @moduledoc """
  SIS (Student Information System) integration identifiers from LIS.

  All fields are optional. `:person_source_id` identifies the user in the SIS, and `:course_offering_source_id` and `:course_section_source_id` identify the course offering and section.

  ## Examples

      iex> Ltix.LaunchClaims.LIS.from_json(%{"person_sourcedid" => "sis-001"})
      {:ok, %Ltix.LaunchClaims.LIS{person_source_id: "sis-001", course_offering_source_id: nil, course_section_source_id: nil}}
  """

  alias Ltix.LaunchClaims.ClaimHelpers

  # [Core §5.4.5](https://www.imsglobal.org/spec/lti/v1p3/#learning-information-services-lis-claim)
  @struct_schema Zoi.struct(
                   __MODULE__,
                   %{
                     person_source_id: Zoi.string() |> ClaimHelpers.optional(),
                     course_offering_source_id: Zoi.string() |> ClaimHelpers.optional(),
                     course_section_source_id: Zoi.string() |> ClaimHelpers.optional()
                   },
                   coerce: true
                 )

  @schema ClaimHelpers.rename_claims(@struct_schema, %{
            "person_sourcedid" => :person_source_id,
            "course_offering_sourcedid" => :course_offering_source_id,
            "course_section_sourcedid" => :course_section_source_id
          })

  @doc false
  def schema, do: @schema

  @type t :: unquote(Zoi.type_spec(@struct_schema))
  @enforce_keys Zoi.Struct.enforce_keys(@struct_schema)
  defstruct Zoi.Struct.struct_fields(@struct_schema)

  @doc """
  Parse a LIS claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.LIS.from_json(%{})
      {:ok, %Ltix.LaunchClaims.LIS{person_source_id: nil, course_offering_source_id: nil, course_section_source_id: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) do
    ClaimHelpers.from_json(@schema, json, "lis")
  end
end
