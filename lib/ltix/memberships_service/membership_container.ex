defmodule Ltix.MembershipsService.MembershipContainer do
  @moduledoc """
  A roster response from the memberships service.

  Contains the context (course/section) information and a list of
  members. Implements `Enumerable`, so you can pipe it directly into
  `Enum` or `Stream` functions to iterate over members.

  ## Examples

      {:ok, roster} = Ltix.MembershipsService.get_members(client)

      roster.context.id
      #=> "course-123"

      roster
      |> Enum.filter(&(&1.status == :active))
      |> Enum.map(& &1.email)

      Enum.count(roster)
  """

  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.LaunchClaims.Context
  alias Ltix.MembershipsService.Member

  defstruct [:id, :context, members: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          context: Context.t(),
          members: [Member.t()]
        }

  @doc """
  Parse a membership container from a decoded JSON response body.

  Returns `{:ok, container}` on success or `{:error, exception}` if
  the context is missing or a member fails to parse.
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  # [NRPS §2.2] "A context parameter must be present that must contain: id"
  def from_json(%{"context" => context_json} = json) when is_map(context_json) do
    with {:ok, context} <- Context.from_json(context_json),
         {:ok, members} <- parse_members(json["members"] || []) do
      {:ok,
       %__MODULE__{
         id: json["id"],
         context: context,
         members: members
       }}
    end
  end

  def from_json(_) do
    {:error, MissingClaim.exception(claim: "context", spec_ref: "NRPS §2.2")}
  end

  defp parse_members(members) when is_list(members) do
    Enum.reduce_while(members, {:ok, []}, fn member_json, {:ok, acc} ->
      case Member.from_json(member_json) do
        {:ok, member} -> {:cont, {:ok, [member | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
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
