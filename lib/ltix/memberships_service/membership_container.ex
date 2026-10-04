defmodule Ltix.MembershipsService.MembershipContainer do
  @moduledoc """
  A roster response from the memberships service.

  Contains the context (course/section) information and a list of
  members. Implements `Enumerable`, so you can pipe it directly into
  `Enum` or `Stream` functions to iterate over members.

  ## Examples

      {:ok, roster} = Ltix.MembershipsService.list_members(client)

      roster.context.id
      #=> "course-123"

      roster
      |> Enum.filter(&(&1.status == :active))
      |> Enum.map(& &1.email)

      Enum.count(roster)
  """

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.LaunchClaims.Context
  alias Ltix.LaunchClaims.Role
  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Member

  defstruct [:id, :context, members: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          context: Context.t(),
          members: [Member.t()]
        }

  @doc """
  Parse a membership container from a decoded JSON response body.

  Returns `{:ok, container}` on success or `{:error, exception}` if the body
  is not a membership container or a member fails to parse.
  """
  @spec from_json(term()) :: {:ok, t()} | {:error, Exception.t()}
  # [membership-container-media-type]:
  # https://www.imsglobal.org/spec/lti-nrps/v2p0/#membership-container-media-type
  #
  # [NRPS §2.1][membership-container-media-type]
  def from_json(%{"members" => members} = json) when is_list(members) do
    with :ok <- validate_id(json["id"]),
         {:ok, context} <- parse_context(json["context"]),
         {:ok, members} <- parse_members(members) do
      {:ok, %__MODULE__{id: json["id"], context: context, members: members}}
    end
  end

  def from_json(json) when is_map(json), do: malformed("expected members to be a JSON array")
  def from_json(_json), do: malformed("expected JSON object")

  # [sharing-of-personal-data]:
  # https://www.imsglobal.org/spec/lti-nrps/v2p0/#sharing-of-personal-data
  #
  # [NRPS §2.2][sharing-of-personal-data]
  defp parse_context(nil), do: Context.from_json(%{})
  defp parse_context(context), do: Context.from_json(context)

  defp validate_id(id) when is_nil(id) or is_binary(id), do: :ok

  defp validate_id(id) do
    {:error,
     InvalidClaim.exception(
       claim: "membership.id",
       value: id,
       message: "must be a string",
       spec_ref: "NRPS §2.1"
     )}
  end

  defp parse_members(members) do
    role_parsers = Role.parsers([])

    members
    |> Enum.reduce_while({:ok, []}, fn member_json, {:ok, acc} ->
      case Member.from_json(member_json, role_parsers) do
        {:ok, member} -> {:cont, {:ok, [member | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp malformed(reason) do
    {:error,
     MalformedResponse.exception(
       service: MembershipsService,
       reason: reason,
       spec_ref: "NRPS §2.1"
     )}
  end
end

defimpl Enumerable, for: Ltix.MembershipsService.MembershipContainer do
  def count(%{members: members}), do: {:ok, length(members)}

  def member?(%{members: members}, element), do: {:ok, element in members}

  def reduce(%{members: members}, acc, fun), do: Enumerable.List.reduce(members, acc, fun)

  def slice(%{members: members}) do
    size = length(members)

    {:ok, size,
     fn start, length, step ->
       members
       |> Enum.drop(start)
       |> Enum.take(length * step)
       |> Enum.take_every(step)
     end}
  end
end
