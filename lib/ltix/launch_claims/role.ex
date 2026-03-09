defmodule Ltix.LaunchClaims.Role do
  @moduledoc """
  A parsed LTI role with type, name, and optional sub-role.

  Roles arrive in launch claims as URI strings. Use `parse/1` to convert
  a single URI, or access them pre-parsed via `context.claims.roles`.

  ## Checking Roles

  Predicate helpers like `instructor?/1` and `learner?/1` match on the
  role name regardless of sub-role. This means `instructor?/1` returns
  `true` for both a principal Instructor and an Instructor#TeachingAssistant:

      Role.instructor?(launch.claims.roles)

  To check for a specific sub-role, use `teaching_assistant?/1` or
  `has_role?/4`:

      Role.teaching_assistant?(roles)
      Role.has_role?(roles, :context, :instructor, :teaching_assistant)

  To check for _only_ the principal role (excluding sub-roles), pass
  `nil` as the sub-role:

      Role.has_role?(roles, :context, :instructor, nil)

  ## Role Types

    * `:context` — course-level roles (Instructor, Learner, etc.)
    * `:institution` — institution-level roles (Faculty, Student, etc.)
    * `:system` — system-level roles (Administrator, SysAdmin, etc.)

  Use the filter helpers to narrow by type:

      Role.context_roles(roles)
      Role.institution_roles(roles)

  ## Examples

      iex> Ltix.LaunchClaims.Role.parse("http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor")
      {:ok, %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: nil, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"}}

      iex> Ltix.LaunchClaims.Role.parse("Instructor")
      {:ok, %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: nil, uri: "Instructor"}}

      iex> Ltix.LaunchClaims.Role.parse("http://example.com/unknown")
      :error
  """

  alias Ltix.LaunchClaims.Role.LIS

  defstruct [:type, :name, :sub_role, :uri]

  @type t :: %__MODULE__{
          type: :context | :institution | :system,
          name: atom(),
          sub_role: atom() | nil,
          uri: String.t()
        }

  @type t_without_uri :: %__MODULE__{
          type: :context | :institution | :system,
          name: atom(),
          sub_role: atom() | nil,
          uri: nil
        }

  # Short context role names
  # [Cert §6.1.2](https://www.imsglobal.org/spec/lti/v1p3/cert#valid-teacher-launches)
  @short_context_roles %{
    "Administrator" => :administrator,
    "ContentDeveloper" => :content_developer,
    "Instructor" => :instructor,
    "Learner" => :learner,
    "Mentor" => :mentor,
    "Manager" => :manager,
    "Member" => :member,
    "Officer" => :officer
  }

  # --- Public API ---

  @doc """
  Parse a single role URI into a `%Role{}` struct.

  Tries registered parsers by URI prefix, then falls back to short
  context role names. The LIS vocabulary parser is registered by default.

  Returns `{:ok, %Role{}}` for recognized roles, `:error` for unknown URIs.

  ## Examples

      iex> Ltix.LaunchClaims.Role.parse("http://purl.imsglobal.org/vocab/lis/v2/membership#Learner")
      {:ok, %Ltix.LaunchClaims.Role{type: :context, name: :learner, sub_role: nil, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"}}

      iex> Ltix.LaunchClaims.Role.parse("http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant")
      {:ok, %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: :teaching_assistant, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"}}
  """
  @spec parse(String.t(), keyword()) :: {:ok, t()} | :error
  def parse(uri, opts \\ []) when is_binary(uri) do
    parsers =
      opts
      |> Keyword.get(:parsers, %{})
      |> Map.put_new("http://purl.imsglobal.org/vocab/", &LIS.parse/1)

    application_parsers = Application.get_env(:ltix, __MODULE__, []) |> Keyword.get(:parsers, %{})
    parsers = Map.merge(application_parsers, parsers)

    with :error <- try_parsers(uri, parsers) do
      parse_short_name(uri)
    end
  end

  @doc """
  Parse a list of role URIs, separating recognized from unrecognized.

  Returns `{parsed_roles, unrecognized_uris}` where order is preserved.

  ## Examples

      iex> Ltix.LaunchClaims.Role.parse_all([])
      {[], []}
  """
  @spec parse_all([String.t()], keyword()) :: {[t()], [String.t()]}
  def parse_all(uris, opts \\ []) when is_list(uris) do
    Enum.reduce(uris, {[], []}, fn uri, {parsed, unrecognized} ->
      case parse(uri, opts) do
        {:ok, role} -> {[role | parsed], unrecognized}
        :error -> {parsed, [uri | unrecognized]}
      end
    end)
    |> then(fn {p, u} -> {Enum.reverse(p), Enum.reverse(u)} end)
  end

  @doc """
  Convert a `%Role{}` struct to its URI string.

  Tries each registered parser's `to_uri/1` callback until one succeeds.
  The LIS parser is tried by default.

  ## Examples

      iex> role = %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: nil}
      iex> Ltix.LaunchClaims.Role.to_uri(role)
      {:ok, "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"}

      iex> role = %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: :teaching_assistant}
      iex> Ltix.LaunchClaims.Role.to_uri(role)
      {:ok, "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"}
  """
  @spec to_uri(t_without_uri()) :: {:ok, String.t()} | :error
  def to_uri(%__MODULE__{} = role) do
    app_parsers =
      Application.get_env(:ltix, __MODULE__, [])
      |> Keyword.get(:to_uri_parsers, [])

    [LIS | app_parsers]
    |> Enum.filter(fn parser ->
      Code.ensure_loaded?(parser) and function_exported?(parser, :to_uri, 1)
    end)
    |> Enum.find_value(:error, fn parser ->
      case parser.to_uri(role) do
        {:ok, _} = ok -> ok
        :error -> nil
      end
    end)
  end

  # --- Constructors ---

  @doc """
  Build a role from a well-known atom.

  Supports common context roles, one sub-role, and a handful of
  institution and system roles. Raises `ArgumentError` for unknown atoms.

  ## Context roles

      iex> Ltix.LaunchClaims.Role.from_atom(:instructor)
      %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: nil, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"}

      iex> Ltix.LaunchClaims.Role.from_atom(:learner)
      %Ltix.LaunchClaims.Role{type: :context, name: :learner, sub_role: nil, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"}

  ## Sub-roles

      iex> Ltix.LaunchClaims.Role.from_atom(:teaching_assistant)
      %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: :teaching_assistant, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"}

  ## Institution roles

      iex> Ltix.LaunchClaims.Role.from_atom(:faculty)
      %Ltix.LaunchClaims.Role{type: :institution, name: :faculty, sub_role: nil, uri: "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty"}

  ## System roles

      iex> Ltix.LaunchClaims.Role.from_atom(:test_user)
      %Ltix.LaunchClaims.Role{type: :system, name: :test_user, sub_role: nil, uri: "http://purl.imsglobal.org/vocab/lti/system/person#TestUser"}
  """
  @spec from_atom(atom()) :: t()
  # Context principals
  def from_atom(:instructor),
    do: %__MODULE__{
      type: :context,
      name: :instructor,
      sub_role: nil,
      uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
    }

  def from_atom(:learner),
    do: %__MODULE__{
      type: :context,
      name: :learner,
      sub_role: nil,
      uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"
    }

  def from_atom(:content_developer),
    do: %__MODULE__{
      type: :context,
      name: :content_developer,
      sub_role: nil,
      uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#ContentDeveloper"
    }

  def from_atom(:mentor),
    do: %__MODULE__{
      type: :context,
      name: :mentor,
      sub_role: nil,
      uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Mentor"
    }

  # Context sub-roles
  def from_atom(:teaching_assistant),
    do: %__MODULE__{
      type: :context,
      name: :instructor,
      sub_role: :teaching_assistant,
      uri: "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"
    }

  # Institution roles
  def from_atom(:administrator),
    do: %__MODULE__{
      type: :institution,
      name: :administrator,
      sub_role: nil,
      uri: "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Administrator"
    }

  def from_atom(:faculty),
    do: %__MODULE__{
      type: :institution,
      name: :faculty,
      sub_role: nil,
      uri: "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Faculty"
    }

  def from_atom(:student),
    do: %__MODULE__{
      type: :institution,
      name: :student,
      sub_role: nil,
      uri: "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Student"
    }

  def from_atom(:staff),
    do: %__MODULE__{
      type: :institution,
      name: :staff,
      sub_role: nil,
      uri: "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Staff"
    }

  # System roles
  def from_atom(:test_user),
    do: %__MODULE__{
      type: :system,
      name: :test_user,
      sub_role: nil,
      uri: "http://purl.imsglobal.org/vocab/lti/system/person#TestUser"
    }

  def from_atom(atom) when is_atom(atom) do
    raise ArgumentError, "unknown role atom: #{inspect(atom)}"
  end

  # --- Predicate Helpers ---

  @doc """
  Check if any role is a context Instructor, including sub-roles
  like TeachingAssistant.

  To check for _only_ the principal Instructor role (excluding sub-roles),
  use `has_role?(roles, :context, :instructor, nil)`.
  """
  @spec instructor?([t()]) :: boolean()
  def instructor?(roles), do: has_name?(roles, :context, :instructor)

  @doc """
  Check if any role is a context Learner, including sub-roles
  like GuestLearner.

  To check for _only_ the principal Learner role (excluding sub-roles),
  use `has_role?(roles, :context, :learner, nil)`.
  """
  @spec learner?([t()]) :: boolean()
  def learner?(roles), do: has_name?(roles, :context, :learner)

  @doc "Check if any role is a context Administrator, including sub-roles."
  @spec administrator?([t()]) :: boolean()
  def administrator?(roles), do: has_name?(roles, :context, :administrator)

  @doc "Check if any role is a context ContentDeveloper, including sub-roles."
  @spec content_developer?([t()]) :: boolean()
  def content_developer?(roles), do: has_name?(roles, :context, :content_developer)

  @doc "Check if any role is a context Mentor, including sub-roles."
  @spec mentor?([t()]) :: boolean()
  def mentor?(roles), do: has_name?(roles, :context, :mentor)

  @doc "Check if any role is an Instructor#TeachingAssistant sub-role."
  @spec teaching_assistant?([t()]) :: boolean()
  def teaching_assistant?(roles), do: has_role?(roles, :context, :instructor, :teaching_assistant)

  @doc """
  Check if any role matches the given type, name, and optional sub-role.

  ## Examples

      iex> {:ok, role} = Ltix.LaunchClaims.Role.parse("http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor")
      iex> Ltix.LaunchClaims.Role.has_role?([role], :context, :instructor)
      true
  """
  @spec has_role?([t()], :context | :institution | :system, atom(), atom() | nil) :: boolean()
  def has_role?(roles, type, name, sub_role \\ nil) do
    Enum.any?(roles, fn role ->
      role.type == type and role.name == name and role.sub_role == sub_role
    end)
  end

  # --- Filter Helpers ---

  @doc "Filter to only context roles."
  @spec context_roles([t()]) :: [t()]
  def context_roles(roles), do: Enum.filter(roles, &(&1.type == :context))

  @doc "Filter to only institution roles."
  @spec institution_roles([t()]) :: [t()]
  def institution_roles(roles), do: Enum.filter(roles, &(&1.type == :institution))

  @doc "Filter to only system roles."
  @spec system_roles([t()]) :: [t()]
  def system_roles(roles), do: Enum.filter(roles, &(&1.type == :system))

  # --- Private ---

  # Matches on type and name, ignoring sub_role.
  # [Core §A.2.3.1](https://www.imsglobal.org/spec/lti/v1p3/#context-sub-roles)
  # Platforms SHOULD send the principal role alongside a sub-role, but the
  # tool MUST NOT assume it is always present.
  defp has_name?(roles, type, name) do
    Enum.any?(roles, fn role ->
      role.type == type and role.name == name
    end)
  end

  defp try_parsers(uri, parsers) do
    Enum.find_value(parsers, :error, &try_parser(uri, &1))
  end

  defp try_parser(uri, {prefix, parser}) do
    if String.starts_with?(uri, prefix), do: parser.(uri)
  end

  defp parse_short_name(uri) do
    case Map.fetch(@short_context_roles, uri) do
      {:ok, name} -> {:ok, %__MODULE__{type: :context, name: name, sub_role: nil, uri: uri}}
      :error -> :error
    end
  end
end
