defmodule Ltix.LaunchClaims.ToolPlatform do
  @moduledoc """
  Information about the platform instance that initiated the launch.

  `guid` is required and stable for a given platform instance.

  ## Examples

      iex> Ltix.LaunchClaims.ToolPlatform.from_json(%{"guid" => "plat-1", "name" => "LMS"})
      {:ok, %Ltix.LaunchClaims.ToolPlatform{guid: "plat-1", name: "LMS", contact_email: nil, description: nil, url: nil, product_family_code: nil, version: nil}}
  """

  alias Ltix.Errors.Invalid.MissingClaim

  defstruct [:guid, :name, :contact_email, :description, :url, :product_family_code, :version]

  @type t :: %__MODULE__{
          guid: String.t(),
          name: String.t() | nil,
          contact_email: String.t() | nil,
          description: String.t() | nil,
          url: String.t() | nil,
          product_family_code: String.t() | nil,
          version: String.t() | nil
        }

  @doc """
  Parse a tool platform claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.ToolPlatform.from_json(%{"guid" => "plat-1"})
      {:ok, %Ltix.LaunchClaims.ToolPlatform{guid: "plat-1", name: nil, contact_email: nil, description: nil, url: nil, product_family_code: nil, version: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(%{"guid" => guid} = json) do
    {:ok,
     %__MODULE__{
       guid: guid,
       name: json["name"],
       contact_email: json["contact_email"],
       description: json["description"],
       url: json["url"],
       product_family_code: json["product_family_code"],
       version: json["version"]
     }}
  end

  def from_json(_) do
    {:error, MissingClaim.exception(claim: "tool_platform.guid", spec_ref: "Core §5.4.2")}
  end
end
