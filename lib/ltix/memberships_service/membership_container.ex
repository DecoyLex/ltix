defmodule Ltix.MembershipsService.MembershipContainer do
  @moduledoc """
  A roster response from the memberships service.

  Contains the context (course/section) information and a list of
  members. Implements `Enumerable`, so you can pipe it directly into
  `Enum` or `Stream` functions to iterate over members.

  Plugins add properties to containers with `Ltix.Property`. Read a property
  from `extensions` by its name, as in `roster.extensions.term`.

  ## Examples

      {:ok, roster} = Ltix.MembershipsService.list_members(client)

      roster.context.id
      #=> "course-123"

      roster
      |> Enum.filter(&(&1.status == :active))
      |> Enum.map(& &1.email)

      Enum.count(roster)
  """

  use Ltix.Provider, hook: [Ltix.Property]

  alias Ltix.Claims.Context
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.MembershipsService.Member
  alias Ltix.Type

  # [NRPS, Membership container media type](https://standards.1edtech.org/lti/specifications/services/names_roles/names-role-provisioning-spec#membership-container-media-type)
  use Ltix.Type,
    defaults: [context: nil, members: []],
    fields: [
      id: Zoi.string(metadata: [strict: true]) |> Zoi.optional(),
      context: Zoi.struct(Context, metadata: [from_json: &__MODULE__.parse_context/2]),
      members: Zoi.list(Zoi.struct(Member), metadata: [from_json: &__MODULE__.parse_members/2])
    ]

  # Parses the context as a launch's context claim, with its properties. A
  # `null` context is missing its ID.
  # [Core, Context claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#context-claim)
  @doc false
  @spec parse_context(term(), keyword()) :: {:ok, Context.t()} | {:error, Exception.t()}
  def parse_context(json, opts) do
    Type.from_json(Context, json || %{}, plugins: Keyword.fetch!(opts, :plugins), name: "context")
  end

  # Parses each member with the `:plugins` of `opts`, and runs the claims'
  # checks on its messages. Returns the first error.
  @doc false
  @spec parse_members(term(), keyword()) :: {:ok, [Member.t()]} | {:error, term()}
  def parse_members(members, opts) when is_list(members) do
    plugins = Keyword.fetch!(opts, :plugins)

    parsed =
      Enum.reduce_while(members, {:ok, []}, fn json, {:ok, parsed} ->
        case parse_member(json, plugins) do
          {:ok, member} -> {:cont, {:ok, [member | parsed]}}
          {:error, _error} = error -> {:halt, error}
        end
      end)

    with {:ok, parsed} <- parsed, do: {:ok, Enum.reverse(parsed)}
  end

  def parse_members(_members, _opts), do: {:error, "must be an array"}

  @doc """
  Adds an anonymous property of membership containers to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)

  # A member with neither `user_id` nor `roles` is reported once.
  # [NRPS, Sharing of personal data](https://standards.1edtech.org/lti/specifications/services/names_roles/names-role-provisioning-spec#sharing-of-personal-data)
  defp parse_member(json, plugins)
       when is_map_key(json, "user_id") or is_map_key(json, "roles") do
    with {:ok, member} <- Type.from_json(Member, json, plugins: plugins, name: "member"),
         :ok <- Member.check_messages(member, json, plugins),
         do: {:ok, member}
  end

  defp parse_member(_json, _plugins) do
    {:error, MissingClaim.exception(claim: "member.user_id and member.roles")}
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
