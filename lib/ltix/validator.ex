defmodule Ltix.Validator do
  @moduledoc """
  The required and optional claims of a message type, built from requirements
  for each claim.

  Message types build validators (see `Ltix.Launch.MessageType`). Requirements
  refer to claims by short name.

      new("LtiResourceLinkRequest")
      |> required(:resource_link)
      |> required(:roles)
      |> required(:subject, unless: option(:allow_anonymous))

  ## Combining requirements

  Plugin order doesn't change which claims are required.

    * A claim is required when a `required/3` call for it applies, even when an
      `optional/3` call applies too.
    * `override/3` sets whether a claim is required, regardless of the other
      requirements. It's the only way to make a required claim optional.

  ## Conditions

  `required/3` and `optional/3` take a `t:condition/0` as `when:` or `unless:`.
  """

  alias Ltix.Validator.Includes
  alias Ltix.Validator.Option

  defstruct message_type: nil, requirements: []

  @typedoc """
  A validator. `message_type` is the message type it validates, or `nil` for
  launches of a message type no plugin declares. `requirements` is internal.
  """
  @type t :: %__MODULE__{message_type: String.t() | nil, requirements: [requirement()]}

  @typedoc "A claim's short name, such as `:roles`."
  @type claim :: atom()

  @typedoc "Whether a message must have a claim."
  @type presence :: :required | :optional

  @typedoc """
  A condition from `option/1` or `includes/3`, or an `Ltix.Validator.Condition`.
  """
  @type condition :: module() | {module(), list()}

  # `kind` is `:statement` for `required/3` and `optional/3`, and `source`
  # is the module that made the statement, once a plugin set is resolved.
  @typep requirement ::
           {kind :: :statement | :override | :default, claim(), presence(), condition :: term(),
            source :: module() | nil}

  # Imports the builders, for message types and contributions.
  @doc false
  defmacro __using__(_opts) do
    quote do
      import Ltix.Validator,
        only: [
          new: 1,
          required: 2,
          required: 3,
          optional: 2,
          optional: 3,
          override: 3,
          defaults: 2,
          option: 1,
          includes: 3
        ],
        warn: false
    end
  end

  @doc """
  Returns a validator with no requirements for a message type.

      iex> Ltix.Validator.new("LtiResourceLinkRequest").message_type
      "LtiResourceLinkRequest"
  """
  @spec new(String.t()) :: t()
  def new(message_type) when is_binary(message_type), do: %__MODULE__{message_type: message_type}

  @condition_schema Zoi.keyword(
                      [
                        when:
                          Zoi.any(
                            description:
                              "A `t:condition/0`. The requirement applies only when the condition is met."
                          ),
                        unless:
                          Zoi.any(
                            description:
                              "A `t:condition/0`. The requirement applies only when the condition isn't met."
                          )
                      ],
                      unrecognized_keys: :error
                    )

  @doc """
  States that a message must have `claim`.

      iex> validator =
      ...>   Ltix.Validator.new("LtiResourceLinkRequest")
      ...>   |> Ltix.Validator.required(:roles)
      ...>   |> Ltix.Validator.required(:subject, unless: Ltix.Validator.option(:allow_anonymous))
      iex> Ltix.Validator.missing(validator, %{roles: []}, allow_anonymous: false)
      [:subject]
      iex> Ltix.Validator.missing(validator, %{roles: []}, allow_anonymous: true)
      []

  ## Options

  Pass at most one of these.

  #{Zoi.describe(@condition_schema)}
  """
  @spec required(validator :: t(), claim :: claim(), opts :: keyword()) :: t()
  def required(%__MODULE__{} = validator, claim, opts \\ []) when is_atom(claim),
    do: state(validator, claim, :required, opts)

  @doc """
  States that a message may have `claim`.

      iex> Ltix.Validator.new("LtiDeepLinkingRequest")
      ...> |> Ltix.Validator.optional(:roles)
      ...> |> Ltix.Validator.missing(%{}, [])
      []
      iex> Ltix.Validator.new("LtiDeepLinkingRequest")
      ...> |> Ltix.Validator.optional(:roles)
      ...> |> Ltix.Validator.required(:roles)
      ...> |> Ltix.Validator.missing(%{}, [])
      [:roles]

  ## Options

  Pass at most one of these.

  #{Zoi.describe(@condition_schema)}
  """
  @spec optional(validator :: t(), claim :: claim(), opts :: keyword()) :: t()
  def optional(%__MODULE__{} = validator, claim, opts \\ []) when is_atom(claim),
    do: state(validator, claim, :optional, opts)

  @doc """
  Makes `claim` required or optional.

  When one module overrides a claim more than once, its last override applies.
  Two modules that override the same claim in one message type are a
  [conflict](`m:Ltix.Launch.MessageType#module-conflicts`).

      iex> Ltix.Validator.new("LtiResourceLinkRequest")
      ...> |> Ltix.Validator.required(:roles)
      ...> |> Ltix.Validator.override(:roles, :optional)
      ...> |> Ltix.Validator.missing(%{}, [])
      []
  """
  @spec override(validator :: t(), claim :: claim(), presence :: presence()) :: t()
  def override(%__MODULE__{} = validator, claim, presence)
      when is_atom(claim) and presence in [:required, :optional],
      do: add(validator, [{:override, claim, presence, nil, nil}])

  @doc """
  States several claims in one call.

  It's the same as `required/3` for each claim in `required:`, and `optional/3`
  for each claim in `optional:`, without conditions.

      iex> Ltix.Validator.new("LtiResourceLinkRequest")
      ...> |> Ltix.Validator.optional(:context)
      ...> |> Ltix.Validator.defaults(required: [:context, :tool_platform])
      ...> |> Ltix.Validator.missing(%{}, [])
      [:context, :tool_platform]
  """
  @spec defaults(t(), required: [claim()], optional: [claim()]) :: t()
  def defaults(%__MODULE__{} = validator, defaults) when is_list(defaults) do
    requirements =
      for {presence, claims} <- Keyword.validate!(defaults, required: [], optional: []),
          claim <- claims,
          do: {:default, claim, presence, nil, nil}

    add(validator, requirements)
  end

  @doc """
  Returns a condition that is met when the `Ltix.handle_callback/3` option
  `key` is `true`, such as `allow_anonymous: true`.

      iex> Ltix.Validator.new("LtiResourceLinkRequest")
      ...> |> Ltix.Validator.required(:subject, unless: Ltix.Validator.option(:allow_anonymous))
      ...> |> Ltix.Validator.missing(%{}, allow_anonymous: true)
      []
  """
  @spec option(key :: atom()) :: condition()
  def option(key) when is_atom(key), do: {Option, [key]}

  @doc """
  Returns a condition that is met when `field` of the object claim `claim` is
  `value`, or is a list that includes it.

      iex> validator =
      ...>   Ltix.Validator.new("LtiDeepLinkingRequest")
      ...>   |> Ltix.Validator.required(:context,
      ...>     when: Ltix.Validator.includes(:deep_linking_settings, :accept_types, "file")
      ...>   )
      iex> Ltix.Validator.missing(validator, %{deep_linking_settings: %{accept_types: ["file"]}}, [])
      [:context]
      iex> Ltix.Validator.missing(validator, %{deep_linking_settings: %{accept_types: ["link"]}}, [])
      []
  """
  @spec includes(claim :: claim(), field :: atom(), value :: term()) :: condition()
  def includes(claim, field, value) when is_atom(claim) and is_atom(field),
    do: {Includes, [claim, field, value]}

  @doc """
  Returns the claims a message must have and doesn't, in the order the validator
  first mentions them.

  Takes the message's parsed claims, keyed by short name, and the options of
  `Ltix.handle_callback/3`, which `option/1` conditions test. A claim is missing
  when it's `nil` or isn't a key in `claims`.

      iex> Ltix.Validator.new("LtiResourceLinkRequest")
      ...> |> Ltix.Validator.required(:resource_link)
      ...> |> Ltix.Validator.required(:roles)
      ...> |> Ltix.Validator.missing(%{resource_link: nil, roles: []}, [])
      [:resource_link]
  """
  @spec missing(validator :: t(), claims :: %{atom() => term()}, opts :: keyword()) :: [claim()]
  def missing(%__MODULE__{} = validator, claims, opts) when is_map(claims) and is_list(opts),
    do: missing(validator, claims, opts, &(claims[&1] == nil))

  # Returns the claims a message must have and `missing?` returns `true` for, in
  # the order the validator first mentions them.
  @doc false
  @spec missing(t(), %{atom() => term()}, keyword(), (claim() -> boolean())) :: [claim()]
  def missing(%__MODULE__{} = validator, claims, opts, missing?) do
    mentioned =
      for {_kind, claim, _presence, _condition, _source} <- validator.requirements,
          uniq: true,
          do: claim

    for claim <- mentioned,
        missing?.(claim),
        required?(validator, claim, claims, opts),
        do: claim
  end

  @doc """
  Describes a validator as a Markdown table, with a row for each requirement it
  states, in order.

  A validator from a resolved plugin set has a column for the module that
  stated each requirement.

      iex> Ltix.Validator.new("LtiResourceLinkRequest")
      ...> |> Ltix.Validator.required(:roles)
      ...> |> Ltix.Validator.required(:subject, unless: Ltix.Validator.option(:allow_anonymous))
      ...> |> Ltix.Validator.optional(:context)
      ...> |> Ltix.Validator.describe()
      \"\"\"
      | Claim | Requirement |
      |---|---|
      | `roles` | Required |
      | `subject` | Required unless the `:allow_anonymous` option is set |
      | `context` | Optional |
      \"\"\"
  """
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{requirements: requirements}) do
    rows =
      for {kind, claim, presence, condition, source} <- requirements,
          do: {"`#{claim}`", requirement(presence) <> qualifier(kind, condition), source}

    if Enum.any?(rows, &elem(&1, 2)) do
      table(
        ["Claim", "Requirement", "Stated by"],
        for({claim, text, source} <- rows, do: [claim, text, source_cell(source)])
      )
    else
      table(["Claim", "Requirement"], for({claim, text, _source} <- rows, do: [claim, text]))
    end
  end

  # Each claim a statement, an override, or a default is about, with the
  # module that made it.
  @doc false
  @spec statement_sources(t()) :: [{claim(), module() | nil}]
  def statement_sources(%__MODULE__{requirements: requirements}),
    do: for({_kind, claim, _presence, _condition, source} <- requirements, do: {claim, source})

  # Each claim an override is about, with the module that made the override.
  @doc false
  @spec override_sources(t()) :: [{claim(), module() | nil}]
  def override_sources(%__MODULE__{requirements: requirements}),
    do:
      for({:override, claim, _presence, _condition, source} <- requirements, do: {claim, source})

  # Records `source` as the module that made the requirements that have none.
  @doc false
  @spec tag(t(), module()) :: t()
  def tag(%__MODULE__{} = validator, source) do
    requirements =
      for {kind, claim, presence, condition, made_by} <- validator.requirements,
          do: {kind, claim, presence, condition, made_by || source}

    %{validator | requirements: requirements}
  end

  defp state(validator, claim, presence, opts),
    do: add(validator, [{:statement, claim, presence, condition(opts), nil}])

  defp add(validator, requirements),
    do: %{validator | requirements: validator.requirements ++ requirements}

  defp condition(opts) do
    case Zoi.parse(@condition_schema, opts) do
      {:ok, []} ->
        nil

      {:ok, [when: condition]} ->
        condition!(condition)

      {:ok, [unless: condition]} ->
        {:not, condition!(condition)}

      _invalid ->
        raise ArgumentError,
              "expected no options, a when: condition, or an unless: condition, got #{inspect(opts)}"
    end
  end

  defp condition!({module, _args} = condition) when is_atom(module) do
    if condition_module?(module),
      do: condition,
      else: raise(ArgumentError, "#{inspect(module)} is not an Ltix.Validator.Condition")
  end

  defp condition!(module) when is_atom(module), do: condition!({module, []})

  defp condition!(other),
    do: raise(ArgumentError, "expected a condition, got #{inspect(other)}")

  defp condition_module?(module),
    do: Code.ensure_compiled(module) == {:module, module} && function_exported?(module, :met?, 3)

  # The last override sets whether the claim is required. Otherwise a
  # required default, or a `required/3` statement that applies, makes it
  # required.
  defp required?(validator, claim, claims, opts) do
    about =
      for {kind, ^claim, presence, condition, _source} <- validator.requirements,
          do: {kind, presence, condition}

    case for({:override, presence, _condition} <- about, do: presence) do
      [] ->
        Enum.any?(about, fn
          {:default, :required, nil} -> true
          {:statement, :required, condition} -> met?(condition, claims, opts)
          _other -> false
        end)

      overrides ->
        List.last(overrides) == :required
    end
  end

  defp met?(nil, _claims, _opts), do: true
  defp met?({:not, condition}, claims, opts), do: !met?(condition, claims, opts)
  defp met?({module, args}, claims, opts), do: module.met?(args, claims, opts)

  defp requirement(:required), do: "Required"
  defp requirement(:optional), do: "Optional"

  defp qualifier(:override, nil), do: " by override"
  defp qualifier(:default, nil), do: ""
  defp qualifier(:statement, nil), do: ""
  defp qualifier(:statement, {:not, {module, args}}), do: " unless " <> module.describe(args)
  defp qualifier(:statement, {module, args}), do: " when " <> module.describe(args)

  defp source_cell(nil), do: ""
  defp source_cell(source), do: "`#{inspect(source)}`"

  defp table(header, rows) do
    separator = "|" <> String.duplicate("---|", length(header))
    Enum.map_join([row(header), separator | Enum.map(rows, &row/1)], &(&1 <> "\n"))
  end

  defp row(cells), do: "| " <> Enum.join(cells, " | ") <> " |"
end
