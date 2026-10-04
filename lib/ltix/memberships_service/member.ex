defmodule Ltix.MembershipsService.Member do
  @moduledoc """
  A single member in a roster response from the memberships service.

  Each member has a `user_id` (matching `sub` from launch JWTs) and
  `roles` (parsed into `%Role{}` structs). Additional fields like
  `name`, `email`, and `picture` depend on platform consent.
  Fields Ltix does not recognize, such as platform-specific extensions,
  are in `extensions` with their original JSON keys.

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
  alias Ltix.LaunchClaims.ClaimHelpers
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
    :lis_person_source_id,
    :lti_1_1_legacy_user_id,
    :message,
    roles: [],
    unrecognized_roles: [],
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
          message: [LaunchClaims.t()] | nil,
          roles: [Role.t()],
          unrecognized_roles: [String.t()],
          extensions: %{optional(String.t()) => term()}
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

  # [standard-claims]:
  # https://openid.net/specs/openid-connect-core-1_0.html#StandardClaims
  #
  # [OIDC §5.1][standard-claims]
  @profile_struct_schema Zoi.struct(
                           __MODULE__,
                           %{
                             name: Zoi.string() |> ClaimHelpers.optional(),
                             picture: Zoi.string() |> ClaimHelpers.optional(),
                             given_name: Zoi.string() |> ClaimHelpers.optional(),
                             family_name: Zoi.string() |> ClaimHelpers.optional(),
                             middle_name: Zoi.string() |> ClaimHelpers.optional(),
                             email: Zoi.string() |> ClaimHelpers.optional(),
                             lis_person_source_id: Zoi.string() |> ClaimHelpers.optional(),
                             lti_1_1_legacy_user_id: Zoi.string() |> ClaimHelpers.optional()
                           },
                           coerce: true
                         )

  @profile_schema ClaimHelpers.rename_claims(
                    @profile_struct_schema,
                    for(
                      {field, key} <- @profile_json_keys,
                      key != Atom.to_string(field),
                      into: %{},
                      do: {key, field}
                    )
                  )

  @doc """
  Parse a member from a JSON map in a membership container response.

  Returns `{:ok, member}` on success or `{:error, exception}` if
  required fields are missing or invalid.
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  # [sharing-of-personal-data]:
  # https://www.imsglobal.org/spec/lti-nrps/v2p0/#sharing-of-personal-data
  #
  # [NRPS §2.2][sharing-of-personal-data]
  def from_json(%{"user_id" => user_id, "roles" => roles} = json) do
    with :ok <- validate_user_id(user_id),
         {:ok, profile} <- ClaimHelpers.from_json(@profile_schema, json, "member", "NRPS §2.2"),
         {:ok, {parsed_roles, unrecognized}} <- parse_roles(roles),
         {:ok, status} <- parse_status(json["status"]),
         {:ok, message} <- parse_message(json["message"]) do
      {:ok,
       %{
         profile
         | user_id: user_id,
           status: status,
           message: message,
           roles: parsed_roles,
           unrecognized_roles: unrecognized,
           extensions: Map.drop(json, @known_keys)
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

  @doc """
  Serialize a member to a map with the JSON keys of a membership container response.

  Fields that are `nil` are omitted, and `extensions` are merged in. The `message` section is not included.

  ## Examples

      iex> member = %Ltix.MembershipsService.Member{
      ...>   user_id: "user-1",
      ...>   status: :active,
      ...>   name: "Jane Doe",
      ...>   roles: [Ltix.LaunchClaims.Role.from_atom(:learner)]
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
      "roles" => Enum.map(member.roles, &Role.to_uri!/1) ++ member.unrecognized_roles
    }

    fields =
      for {field, key} <- @profile_json_keys,
          value = Map.fetch!(member, field),
          not is_nil(value),
          into: required,
          do: {key, value}

    Map.merge(member.extensions, put_status(fields, member.status))
  end

  defp put_status(map, nil), do: map

  defp put_status(map, status), do: Map.put(map, "status", Map.fetch!(@status_strings, status))

  defp validate_user_id(user_id) when is_binary(user_id), do: :ok

  defp validate_user_id(user_id),
    do: invalid_field("user_id", user_id, "must be a string", "NRPS §2.2")

  defp parse_roles(roles) do
    if string_list?(roles) do
      {:ok, Role.parse_all(roles)}
    else
      invalid_field("roles", roles, "must be an array of strings", "NRPS §2.2")
    end
  end

  defp string_list?(values) when is_list(values), do: Enum.all?(values, &is_binary/1)
  defp string_list?(_values), do: false

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
           message: "must be Active, Inactive, or Deleted",
           spec_ref: "NRPS §2.3"
         )}
    end
  end

  defp parse_status(status),
    do: invalid_field("status", status, "must be a string", "NRPS §2.3")

  # [NRPS §3.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#message-section)
  defp parse_message(nil), do: {:ok, nil}

  defp parse_message(messages) when is_list(messages) do
    messages
    |> Enum.reduce_while({:ok, []}, fn msg, {:ok, acc} ->
      case parse_message_entry(msg) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp parse_message(message),
    do: invalid_field("message", message, "must be an array of objects", "NRPS §3.2")

  defp parse_message_entry(message) when is_map(message) do
    LaunchClaims.from_json(message)
  end

  defp parse_message_entry(message),
    do: invalid_field("message", message, "must contain JSON objects", "NRPS §3.2")

  defp invalid_field(field, value, message, spec_ref) do
    {:error,
     InvalidClaim.exception(
       claim: "member.#{field}",
       value: value,
       message: message,
       spec_ref: spec_ref
     )}
  end
end
