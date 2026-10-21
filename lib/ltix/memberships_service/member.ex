defmodule Ltix.MembershipsService.Member do
  @moduledoc """
  A single member in a roster response from the memberships service.

  Each member has a `user_id` (matching `sub` from launch JWTs) and
  `roles`, the role URIs the platform sent. Check them with `Ltix.Role`.
  Additional fields like `name`, `email`, and `picture` depend on platform
  consent.
  Fields Ltix does not recognize, such as platform-specific extensions,
  are in `extensions` with their original JSON keys. A member's `message`
  has the claims of each message the platform sent about the member, parsed
  as a launch's claims are.

  ## Examples

      {:ok, plugins} = Ltix.PluginSet.resolve(nil)

      {:ok, member} = Ltix.MembershipsService.Member.from_json(%{
        "user_id" => "user-1",
        "roles" => ["http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"],
        "name" => "Jane Doe",
        "email" => "jane@example.edu"
      }, plugins)

      member.user_id
      #=> "user-1"

      member.name
      #=> "Jane Doe"

      Ltix.Role.learner?(member.roles)
      #=> true
  """

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Extensions
  alias Ltix.PluginSet

  defstruct [
    :user_id,
    :status,
    :name,
    :picture,
    :given_name,
    :family_name,
    :middle_name,
    :email,
    :lis_person_source_id,
    :lti_1_1_legacy_user_id,
    :message,
    roles: [],
    extensions: %{}
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
          lis_person_source_id: String.t() | nil,
          lti_1_1_legacy_user_id: String.t() | nil,
          message: [%{atom() => term()}] | nil,
          roles: [String.t()],
          extensions: %{optional(String.t()) => term()} | nil
        }

  # [NRPS §2.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#sharing-of-personal-data)
  @profile_json_keys %{
    name: "name",
    picture: "picture",
    given_name: "given_name",
    family_name: "family_name",
    middle_name: "middle_name",
    email: "email",
    lis_person_source_id: "lis_person_sourcedid",
    lti_1_1_legacy_user_id: "lti11_legacy_user_id"
  }

  @known_keys ~w(user_id roles status message) ++ Map.values(@profile_json_keys)

  @status_map %{
    "Active" => :active,
    "Inactive" => :inactive,
    "Deleted" => :deleted
  }

  @status_strings Map.new(@status_map, fn {string, status} -> {status, string} end)

  @doc """
  Parse a member from a JSON map in a membership container response.

  Parses the claims of each `message` with the claims `plugins` declares, as
  `Ltix.Claims.parse/2` does. Returns `{:ok, member}` on success or `{:error, exception}` if
  required fields are missing or invalid.
  """
  @spec from_json(map(), PluginSet.t()) :: {:ok, t()} | {:error, Exception.t()}
  # [sharing-of-personal-data]:
  # https://www.imsglobal.org/spec/lti-nrps/v2p0/#sharing-of-personal-data
  #
  # [NRPS §2.2][sharing-of-personal-data]
  def from_json(%{"user_id" => user_id, "roles" => roles} = json, plugins) do
    with :ok <- validate_user_id(user_id),
         :ok <- validate_roles(roles),
         {:ok, status} <- parse_status(json["status"]),
         {:ok, message} <- parse_message(json["message"], plugins) do
      {:ok,
       struct!(
         __MODULE__,
         profile(json) ++
           [
             user_id: user_id,
             status: status,
             message: message,
             roles: roles,
             extensions: Map.drop(json, @known_keys)
           ]
       )}
    end
  end

  def from_json(%{"user_id" => _}, _plugins) do
    {:error, MissingClaim.exception(claim: "member.roles")}
  end

  def from_json(%{"roles" => _}, _plugins) do
    {:error, MissingClaim.exception(claim: "member.user_id")}
  end

  def from_json(_json, _plugins) do
    {:error, MissingClaim.exception(claim: "member.user_id and member.roles")}
  end

  @doc """
  Serialize a member to a map with the JSON keys of a membership container response.

  Fields that are `nil` are omitted, and `extensions` are merged in. The `message` section is not included.

  ## Examples

      iex> member = %Ltix.MembershipsService.Member{
      ...>   user_id: "user-1",
      ...>   status: :active,
      ...>   name: "Jane Doe",
      ...>   roles: [Ltix.Role.context_learner()]
      ...> }
      iex> Ltix.MembershipsService.Member.to_map(member)
      %{
        "user_id" => "user-1",
        "status" => "Active",
        "name" => "Jane Doe",
        "roles" => ["http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"]
      }
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = member) do
    required = %{
      "user_id" => member.user_id,
      "roles" => member.roles
    }

    fields =
      for {field, key} <- @profile_json_keys,
          value <- [Map.fetch!(member, field)],
          not is_nil(value),
          into: required,
          do: {key, value}

    Extensions.merge(put_status(fields, member.status), member.extensions)
  end

  # A profile field that isn't a string is `nil`.
  #
  # [standard-claims]:
  # https://openid.net/specs/openid-connect-core-1_0.html#StandardClaims
  #
  # [OIDC §5.1][standard-claims]
  defp profile(json) do
    for {field, key} <- @profile_json_keys, is_binary(json[key]), do: {field, json[key]}
  end

  defp put_status(map, nil), do: map

  defp put_status(map, status), do: Map.put(map, "status", Map.fetch!(@status_strings, status))

  defp validate_user_id(user_id) when is_binary(user_id), do: :ok

  defp validate_user_id(user_id),
    do: invalid_field("user_id", user_id, "must be a string")

  defp validate_roles(roles) when is_list(roles) do
    if Enum.all?(roles, &is_binary/1), do: :ok, else: invalid_roles(roles)
  end

  defp validate_roles(roles), do: invalid_roles(roles)

  defp invalid_roles(roles),
    do: invalid_field("roles", roles, "must be an array of strings")

  # [NRPS §2.3](https://www.imsglobal.org/spec/lti-nrps/v2p0/#membership-status)
  defp parse_status(nil), do: {:ok, :active}

  defp parse_status(status) when is_binary(status) do
    # Allow minor platform variations in status formatting.
    normalized =
      status
      |> String.trim()
      |> String.downcase()
      |> String.capitalize()

    case Map.fetch(@status_map, normalized) do
      {:ok, atom} ->
        {:ok, atom}

      :error ->
        {:error,
         InvalidClaim.exception(
           claim: "member.status",
           value: status,
           message: "must be Active, Inactive, or Deleted"
         )}
    end
  end

  defp parse_status(status),
    do: invalid_field("status", status, "must be a string")

  # [NRPS §3.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#message-section)
  defp parse_message(nil, _plugins), do: {:ok, nil}

  defp parse_message(messages, plugins) when is_list(messages) do
    messages
    |> Enum.reduce_while({:ok, []}, fn msg, {:ok, acc} ->
      case parse_message_entry(msg, plugins) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp parse_message(message, _plugins),
    do: invalid_field("message", message, "must be an array of objects")

  defp parse_message_entry(message, plugins) when is_map(message) do
    case Ltix.Claims.parse(message, plugins) do
      {:ok, claims, _endpoints} -> {:ok, claims}
      {:error, error, _claims, _endpoints} -> {:error, error}
    end
  end

  defp parse_message_entry(message, _plugins),
    do: invalid_field("message", message, "must contain JSON objects")

  defp invalid_field(field, value, message) do
    {:error, InvalidClaim.exception(claim: "member.#{field}", value: value, message: message)}
  end
end
