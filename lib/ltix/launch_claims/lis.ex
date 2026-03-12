defmodule Ltix.LaunchClaims.Lis do
  @moduledoc """
  SIS (Student Information System) integration identifiers from LIS.

  All fields are optional.

  ## Examples

      iex> Ltix.LaunchClaims.Lis.from_json(%{"person_sourcedid" => "sis-001"})
      {:ok, %Ltix.LaunchClaims.Lis{person_sourcedid: "sis-001", course_offering_sourcedid: nil, course_section_sourcedid: nil}}
  """

  alias Ltix.LaunchClaims.ClaimHelpers

  # [Core §5.4.5](https://www.imsglobal.org/spec/lti/v1p3/#learning-information-services-lis-claim)
  @schema Zoi.struct(
            __MODULE__,
            %{
              person_sourcedid: Zoi.string(coerce: true) |> Zoi.optional(),
              course_offering_sourcedid: Zoi.string(coerce: true) |> Zoi.optional(),
              course_section_sourcedid: Zoi.string(coerce: true) |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Parse a LIS claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.Lis.from_json(%{})
      {:ok, %Ltix.LaunchClaims.Lis{person_sourcedid: nil, course_offering_sourcedid: nil, course_section_sourcedid: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) when is_map(json) do
    ClaimHelpers.from_json(@schema, json, "lis", "Core §5.4.5")
  end
end
