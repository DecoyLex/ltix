defmodule Ltix.MembershipsService.Member do
  @moduledoc """
  A single member in a roster response from the memberships service.

  Each member has a `user_id` (matching `sub` from launch JWTs) and
  `roles` (parsed into `%Role{}` structs). Additional fields like
  `name`, `email`, and `picture` depend on platform consent.

  ## Examples

      {:ok, member} = Ltix.MembershipsService.Member.from_json(%{
        "user_id" => "user-1",
        "roles" => ["http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"],
        "name" => "Jane Doe",
        "email" => "jane@example.edu"
      })

      member.user_id
      #=> "user-1"

      member.name
      #=> "Jane Doe"

      hd(member.roles).name
      #=> :learner
  """

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.LaunchClaims
  alias Ltix.LaunchClaims.Role

  defstruct [
    :user_id,
    :status,
    :name,
    :picture,
    :given_name,
    :family_name,
    :middle_name,
    :email,
    :lis_person_sourcedid,
    :lti11_legacy_user_id,
    :message,
    roles: [],
    unrecognized_roles: []
  ]

  @type t :: %__MODULE__{
          user_id: String.t(),
          status: :active | :inactive | :deleted,
          name: String.t() | nil,
          picture: String.t() | nil,
          given_name: String.t() | nil,
          family_name: String.t() | nil,
          middle_name: String.t() | nil,
          email: String.t() | nil,
          lis_person_sourcedid: String.t() | nil,
          lti11_legacy_user_id: String.t() | nil,
          message: [LaunchClaims.t()] | nil,
          roles: [Role.t()],
          unrecognized_roles: [String.t()]
        }

  @status_map %{
    "Active" => :active,
    "Inactive" => :inactive,
    "Deleted" => :deleted
  }

  @doc """
  Parse a member from a JSON map in a membership container response.

  Returns `{:ok, member}` on success or `{:error, exception}` if
  required fields are missing or invalid.
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  # [NRPS §2.2] "At a minimum, the member must contain: user_id and roles"
  def from_json(%{"user_id" => user_id, "roles" => roles} = json)
      when is_binary(user_id) and is_list(roles) do
    {parsed_roles, unrecognized} = Role.parse_all(roles)

    with {:ok, status} <- parse_status(json["status"]),
         {:ok, message} <- parse_message(json["message"]) do
      {:ok,
       %__MODULE__{
         user_id: user_id,
         status: status,
         name: json["name"],
         picture: json["picture"],
         given_name: json["given_name"],
         family_name: json["family_name"],
         middle_name: json["middle_name"],
         email: json["email"],
         lis_person_sourcedid: json["lis_person_sourcedid"],
         lti11_legacy_user_id: json["lti11_legacy_user_id"],
         message: message,
         roles: parsed_roles,
         unrecognized_roles: unrecognized
       }}
    end
  end

  def from_json(%{"user_id" => _}) do
    {:error, MissingClaim.exception(claim: "member.roles", spec_ref: "NRPS §2.2")}
  end

  def from_json(%{"roles" => _}) do
    {:error, MissingClaim.exception(claim: "member.user_id", spec_ref: "NRPS §2.2")}
  end

  def from_json(_) do
    {:error,
     MissingClaim.exception(claim: "member.user_id and member.roles", spec_ref: "NRPS §2.2")}
  end

  # [NRPS §2.3] "If the status is not specified then a status of Active must be assumed."
  defp parse_status(nil), do: {:ok, :active}

  defp parse_status(status_string) when is_binary(status_string) do
    # Robustness: downcase and trim whitespace to allow for minor platform variations
    status_string =
      status_string
      |> String.trim()
      |> String.downcase()
      |> String.capitalize()

    case Map.fetch(@status_map, status_string) do
      {:ok, atom} ->
        {:ok, atom}

      :error ->
        {:error,
         InvalidClaim.exception(
           claim: "member.status",
           value: status_string,
           message: "must be Active, Inactive, or Deleted",
           spec_ref: "NRPS §2.3"
         )}
    end
  end

  # [NRPS §3.2] Message section uses LTI 1.3 claims format
  defp parse_message(nil), do: {:ok, nil}
  defp parse_message([]), do: {:ok, []}

  defp parse_message(messages) when is_list(messages) do
    messages
    |> Enum.reduce_while({:ok, []}, fn msg, {:ok, acc} ->
      case LaunchClaims.from_json(msg) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end
end
