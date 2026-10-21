defmodule Ltix.MembershipsService.Member do
  @moduledoc """
  A member of a context, from a roster the memberships service returns.

  Check a member's `roles` with `Ltix.Role`. Profile fields such as `name`
  and `email` depend on what the platform shares, and are `nil` when
  missing or malformed.

  Plugins add properties to members with `Ltix.Property`. Read a property from
  `extensions` by its name, as in `member.extensions.student_number`.

  ## Messages

  When you pass `:resource_link_id` to
  `Ltix.MembershipsService.list_members/2` or
  `Ltix.MembershipsService.stream_members/2`, each member can have a
  `message` list. A message is a claims map like `launch.claims`, with the
  claims the platform would send in the member's launches of that resource
  link.

      {:ok, roster} = Ltix.MembershipsService.list_members(client, resource_link_id: "rl-42")

      for member <- roster, message <- member.message || [] do
        {member.user_id, message.custom}
      end

  A message can leave out claims that a launch requires. Ltix checks the claims
  it has the same way as in a launch.

  ## Fields

    * `:user_id` - the member's subject identifier, which matches the `sub`
      of their launches
    * `:roles` - the member's role URIs in the context
    * `:status` - `:active`, `:inactive`, or `:deleted`. Defaults to
      `:active`
    * `:name`, `:given_name`, `:family_name`, `:middle_name`, `:email`, and
      `:picture` - the member's profile
    * `:lis_person_source_id` - the member's ID in the institution's student
      information system
    * `:lti_1_1_legacy_user_id` - the member's user ID in LTI 1.1 launches
    * `:message` - the member's messages, or `nil`
  """

  use Ltix.Provider, hook: [Ltix.Property]

  alias Ltix.Claims

  # [NRPS §2.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#sharing-of-personal-data)
  use Ltix.Type,
    defaults: [user_id: nil, roles: []],
    fields: [
      user_id: Zoi.string(),
      roles: Zoi.list(Zoi.string()),
      # [NRPS §2.3](https://www.imsglobal.org/spec/lti-nrps/v2p0/#membership-status)
      status:
        Zoi.enum([:active, :inactive, :deleted],
          metadata: [
            from_json: &__MODULE__.parse_status/1,
            to_json: &__MODULE__.status_to_json/1,
            strict: true
          ]
        )
        |> Zoi.default(:active),
      name: Zoi.string() |> Zoi.optional(),
      picture: Zoi.string() |> Zoi.optional(),
      given_name: Zoi.string() |> Zoi.optional(),
      family_name: Zoi.string() |> Zoi.optional(),
      middle_name: Zoi.string() |> Zoi.optional(),
      email: Zoi.string() |> Zoi.optional(),
      lis_person_source_id:
        Zoi.string(metadata: [json_key: "lis_person_sourcedid"]) |> Zoi.optional(),
      lti_1_1_legacy_user_id:
        Zoi.string(metadata: [json_key: "lti11_legacy_user_id"]) |> Zoi.optional(),
      # [NRPS §3.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#message-section)
      message:
        Zoi.list(Zoi.map(Zoi.atom(), Zoi.any()),
          metadata: [
            from_json: &__MODULE__.parse_message/2,
            strict: true
          ]
        )
        |> Zoi.optional()
    ]

  # Platforms vary the case of the status and pad it with spaces.
  @doc false
  @spec parse_status(term()) :: {:ok, atom()} | {:error, String.t()}
  def parse_status(status) when is_binary(status) do
    case String.downcase(String.trim(status)) do
      "active" -> {:ok, :active}
      "inactive" -> {:ok, :inactive}
      "deleted" -> {:ok, :deleted}
      _other -> {:error, "must be Active, Inactive, or Deleted"}
    end
  end

  def parse_status(_status), do: {:error, "must be a string"}

  @doc false
  @spec status_to_json(atom()) :: String.t()
  def status_to_json(status), do: String.capitalize(Atom.to_string(status))

  # Parses the claims of each message with the `:plugins` of `opts`.
  @doc false
  @spec parse_message(term(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def parse_message(messages, opts) when is_list(messages) do
    plugins = Keyword.fetch!(opts, :plugins)

    parsed =
      Enum.reduce_while(messages, {:ok, []}, fn
        message, {:ok, parsed} when is_map(message) ->
          case Claims.parse(message, plugins) do
            {:ok, claims, _endpoints} -> {:cont, {:ok, [claims | parsed]}}
            {:error, error, _claims, _endpoints} -> {:halt, {:error, error}}
          end

        _message, _parsed ->
          {:halt, {:error, "must contain JSON objects"}}
      end)

    with {:ok, parsed} <- parsed, do: {:ok, Enum.reverse(parsed)}
  end

  def parse_message(_messages, _opts), do: {:error, "must be an array of objects"}

  # Runs the claims' checks on each of the member's messages, for the
  # message's type. A message the platform sent without `roles` is checked
  # with the member's. Takes the member's JSON.
  @doc false
  @spec check_messages(t(), map(), Ltix.PluginSet.t()) :: :ok | {:error, Exception.t()}
  def check_messages(%__MODULE__{message: nil}, _json, _plugins), do: :ok

  def check_messages(%__MODULE__{} = member, %{"message" => sent}, plugins) do
    Ltix.Errors.collect(
      for {claims, json} <- Enum.zip(member.message, sent),
          checked <- [with_member_roles(claims, json, member.roles)],
          {:error, error} <- [Claims.check(checked, claims[:message_type], plugins)],
          do: error
    )
  end

  defp with_member_roles(claims, json, roles) do
    if Map.get(json, "https://purl.imsglobal.org/spec/lti/claim/roles") in [nil, :null],
      do: Map.put(claims, :roles, roles),
      else: claims
  end

  @doc """
  Adds an anonymous property of members to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
