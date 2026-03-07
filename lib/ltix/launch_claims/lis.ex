defmodule Ltix.LaunchClaims.Lis do
  @moduledoc """
  SIS (Student Information System) integration identifiers from LIS.

  All fields are optional.

  ## Examples

      iex> Ltix.LaunchClaims.Lis.from_json(%{"person_sourcedid" => "sis-001"})
      {:ok, %Ltix.LaunchClaims.Lis{person_sourcedid: "sis-001", course_offering_sourcedid: nil, course_section_sourcedid: nil}}
  """

  defstruct [:person_sourcedid, :course_offering_sourcedid, :course_section_sourcedid]

  @type t :: %__MODULE__{
          person_sourcedid: String.t() | nil,
          course_offering_sourcedid: String.t() | nil,
          course_section_sourcedid: String.t() | nil
        }

  @doc """
  Parse a LIS claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.Lis.from_json(%{})
      {:ok, %Ltix.LaunchClaims.Lis{person_sourcedid: nil, course_offering_sourcedid: nil, course_section_sourcedid: nil}}
  """
  @spec from_json(map()) :: {:ok, t()}
  def from_json(json) when is_map(json) do
    {:ok,
     %__MODULE__{
       person_sourcedid: json["person_sourcedid"],
       course_offering_sourcedid: json["course_offering_sourcedid"],
       course_section_sourcedid: json["course_section_sourcedid"]
     }}
  end
end
