defmodule Ltix.LaunchClaims.Role do
  @moduledoc """
  A parsed LTI role with type, name, and optional sub-role.

  Launch claims include roles as URI strings. Use `parse/1` to convert
  a single URI, or access them pre-parsed via `context.claims.roles`.

  ## Checking Roles

  Predicate helpers like `instructor?/1` and `learner?/1` match on the
  role name regardless of sub-role. This means `instructor?/1` returns
  `true` for both a principal Instructor and an Instructor#TeachingAssistant.

      Role.instructor?(launch.claims.roles)

  To check for a specific sub-role, use `teaching_assistant?/1` or
  `has_role?/4`.

      Role.teaching_assistant?(roles)
      Role.has_role?(roles, :context, :instructor, :teaching_assistant)

  To check for _only_ the principal role (excluding sub-roles), pass
  `nil` as the sub-role.

      Role.has_role?(roles, :context, :instructor, nil)

  ## Role Types

    * `:context` - course-level roles (Instructor, Learner, etc.)
    * `:institution` - institution-level roles (Faculty, Student, etc.)
    * `:system` - system-level roles (Administrator, SysAdmin, etc.)

  Use the filter helpers to narrow by type.

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

  alias Ltix.AppConfig
  alias Ltix.LaunchClaims.Role.LIS
  alias Ltix.Options

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

  @lis_prefix "http://purl.imsglobal.org/vocab/"

  @options_schema Zoi.keyword([role_parsers: Zoi.map(Zoi.string(), Zoi.any())],
                    unrecognized_keys: :error
                  )

  # --- Public API ---

  @doc """
  Parse a single role URI into a `%Role{}` struct.

  Tries parsers whose URI prefix matches, then the built-in LIS parser, then
  short context role names.

  Returns `{:ok, %Role{}}` for recognized roles, `:error` for unknown URIs.

  ## Options

    * `:role_parsers` - map of URI prefix to parser module or function,
      merged over the application configuration. These parsers are tried
      longest prefix first, before the built-in LIS parser.

  ## Examples

      iex> Ltix.LaunchClaims.Role.parse("http://purl.imsglobal.org/vocab/lis/v2/membership#Learner")
      {:ok, %Ltix.LaunchClaims.Role{type: :context, name: :learner, sub_role: nil, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"}}

      iex> Ltix.LaunchClaims.Role.parse("http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant")
      {:ok, %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: :teaching_assistant, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"}}
  """
  @spec parse(String.t(), keyword()) :: {:ok, t()} | :error
  def parse(uri, opts \\ []) when is_binary(uri) do
    parse_with(uri, parsers(opts))
  end

  defp parse_with(uri, parsers) do
    Enum.find_value(parsers, &try_parser(uri, &1)) || parse_short_name(uri)
  end

  # Returns the role parsers for `opts`, to parse many roles with
  # `parse_all_with/2`. Configured and per-call parsers come longest prefix
  # first, then the built-in LIS parser. Each is `{prefix, parser, parse}`.
  @doc false
  @spec parsers(keyword()) :: [{String.t(), module() | function(), function()}]
  def parsers(opts) do
    opts = Options.parse!(opts, @options_schema)
    parsers = Map.merge(AppConfig.role_parsers!(), Keyword.get(opts, :role_parsers, %{}))

    by_specificity =
      Enum.sort_by(parsers, fn {prefix, _parser} -> {-byte_size(prefix), prefix} end)

    for {prefix, parser} <- by_specificity ++ [{@lis_prefix, LIS}],
        do: {prefix, parser, Options.parser_function!(parser, :role_parsers)}
  end

  @doc """
  Parse a list of role URIs, separating recognized from unrecognized.

  Returns `{parsed_roles, unrecognized_uris}` where order is preserved.

  ## Options

    * `:role_parsers` - map of URI prefix to parser module or function,
      merged over the application configuration. These parsers are tried
      longest prefix first, before the built-in LIS parser.

  ## Examples

      iex> Ltix.LaunchClaims.Role.parse_all([])
      {[], []}
  """
  @spec parse_all([String.t()], keyword()) :: {[t()], [String.t()]}
  def parse_all(uris, opts \\ []) when is_list(uris), do: parse_all_with(uris, parsers(opts))

  # Same as `parse_all/2`, with parsers from `parsers/1`.
  @doc false
  @spec parse_all_with([String.t()], list()) :: {[t()], [String.t()]}
  def parse_all_with(uris, parsers) when is_list(uris) do
    {parsed, unrecognized} =
      Enum.reduce(uris, {[], []}, fn uri, {parsed, unrecognized} ->
        case parse_with(uri, parsers) do
          {:ok, role} -> {[role | parsed], unrecognized}
          :error -> {parsed, [uri | unrecognized]}
        end
      end)

    {Enum.reverse(parsed), Enum.reverse(unrecognized)}
  end

  @doc """
  Convert a `%Role{}` struct to its URI string.

  Returns the role's URI, such as one parsed from a launch. For a role
  without one, returns the URI from a role parser module that implements
  `to_uri/1`, or `:error` when none can convert the role.

  ## Options

    * `:role_parsers` - map of URI prefix to parser module or function,
      merged over the application configuration, as for `parse/2`

  ## Examples

      iex> role = %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: nil}
      iex> Ltix.LaunchClaims.Role.to_uri(role)
      {:ok, "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"}

      iex> role = %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: :teaching_assistant}
      iex> Ltix.LaunchClaims.Role.to_uri(role)
      {:ok, "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"}
  """
  @spec to_uri(t() | t_without_uri(), keyword()) :: {:ok, String.t()} | :error
  def to_uri(%__MODULE__{} = role, opts \\ []), do: convert(role, parsers(opts))

  defp convert(%__MODULE__{uri: uri}, _parsers) when is_binary(uri), do: {:ok, uri}
  defp convert(role, parsers), do: Enum.find_value(parsers, :error, &parser_to_uri(&1, role))

  defp parser_to_uri({_prefix, parser, _parse}, role) when is_atom(parser) do
    if function_exported?(parser, :to_uri, 1) do
      case parser.to_uri(role) do
        {:ok, _uri} = converted -> converted
        :error -> nil
      end
    end
  end

  defp parser_to_uri(_function_parser, _role), do: nil

  @doc """
  Same as `to_uri/2` but raises `ArgumentError` when no role parser can convert the role.

  ## Examples

      iex> role = %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: nil}
      iex> Ltix.LaunchClaims.Role.to_uri!(role)
      "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"
  """
  @spec to_uri!(t() | t_without_uri(), keyword()) :: String.t()
  def to_uri!(%__MODULE__{} = role, opts \\ []) do
    case to_uri(role, opts) do
      {:ok, uri} -> uri
      :error -> raise ArgumentError, "no role parser can convert #{inspect(role)} to a URI"
    end
  end

  # --- Constructors ---

  @doc """
  Build a role from a well-known atom.

  Supports common context roles, one sub-role, and a few
  institution and system roles. Raises `ArgumentError` for unknown atoms.

  ## Context roles

      iex> Ltix.LaunchClaims.Role.from_atom(:instructor)
      %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: nil, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"}

      iex> Ltix.LaunchClaims.Role.from_atom(:learner)
      %Ltix.LaunchClaims.Role{type: :context, name: :learner, sub_role: nil, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner"}

      iex> Ltix.LaunchClaims.Role.from_atom(:context_administrator)
      %Ltix.LaunchClaims.Role{type: :context, name: :administrator, sub_role: nil, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Administrator"}

  ## Sub-roles

      iex> Ltix.LaunchClaims.Role.from_atom(:teaching_assistant)
      %Ltix.LaunchClaims.Role{type: :context, name: :instructor, sub_role: :teaching_assistant, uri: "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant"}

  ## Institution roles

      iex> Ltix.LaunchClaims.Role.from_atom(:administrator)
      %Ltix.LaunchClaims.Role{type: :institution, name: :administrator, sub_role: nil, uri: "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Administrator"}

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

  def from_atom(:context_administrator),
    do: %__MODULE__{
      type: :context,
      name: :administrator,
      sub_role: nil,
      uri: "http://purl.imsglobal.org/vocab/lis/v2/membership#Administrator"
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

  @doc "Check if any role is an institution Administrator, including sub-roles."
  @spec administrator?([t()]) :: boolean()
  def administrator?(roles), do: has_name?(roles, :institution, :administrator)

  @doc "Check if any role is a context Administrator, including sub-roles."
  @spec context_administrator?([t()]) :: boolean()
  def context_administrator?(roles), do: has_name?(roles, :context, :administrator)

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

  # Returns the parsed role, or `nil` when the parser's prefix doesn't match or
  # it doesn't recognize the URI.
  defp try_parser(uri, {prefix, _parser, parse}) do
    if String.starts_with?(uri, prefix) do
      case parse.(uri) do
        {:ok, _role} = parsed -> parsed
        :error -> nil
      end
    end
  end

  defp parse_short_name(uri) do
    case Map.fetch(@short_context_roles, uri) do
      {:ok, name} -> {:ok, %__MODULE__{type: :context, name: name, sub_role: nil, uri: uri}}
      :error -> :error
    end
  end
end
