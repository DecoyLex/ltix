defmodule Ltix.Launch.MessageType do
  @moduledoc """
  Declares a message type, such as `LtiResourceLinkRequest`, and the claims its
  launches require.

  A message type's module calls `use Ltix.Launch.MessageType` and builds its
  validator in `c:validator/0` with the imported functions of `Ltix.Validator`.

      defmodule MyLibrary.ReviewRequest do
        @moduledoc "A user opens a submission for review."

        use Ltix.Launch.MessageType

        @impl Ltix.Launch.MessageType
        def validator do
          new("LtiSubmissionReviewRequest")
          |> required(:resource_link)
          |> required(:for_user)
          |> optional(:roles)
        end
      end

  A plugin adds the module with `Ltix.Plugin.add/2`. In this example,
  the plugin would also declare `for_user` (see `Ltix.Claim`), and Core declares
  the others.

  `c:validator/0` must have one clause, and can call only functions of other
  modules, such as those of `Ltix.Validator`. Otherwise the module doesn't
  compile. `use` adds a "Claims" section with a table of the module's
  requirements to its docs, unless it has `@moduledoc false`.

  ## Extending

  Other plugins change what a message type requires with an
  `Ltix.Launch.MessageType.Requirements`.

  ## Conflicts

  Resolution fails with `Ltix.Errors.Unknown.InvalidPluginSet` when

    * two plugins declare the same message type
    * a requirement refers to a claim no plugin declares
    * two modules override the same claim in one message type

  ## Validators

  For a resolved plugin set, `Ltix.PluginSet.data/2` returns a map of
  validators. `:message_types` maps each message type to its validator, with the
  requirements every plugin adds. `:undeclared` has the validator for message
  types no plugin declares. Every plugin set includes Core's message types.

      {:ok, plugins} = Ltix.PluginSet.resolve([])
      %{message_types: validators} = Ltix.PluginSet.data(plugins, Ltix.Launch.MessageType)
      Ltix.Validator.describe(validators["LtiResourceLinkRequest"])
  """
  use Ltix.Provider, hook: [Ltix.Launch.MessageType.Definition]

  alias Ltix.PluginSet
  alias Ltix.PluginSet.Conflict
  alias Ltix.PluginSet.Entry
  alias Ltix.Validator

  @doc """
  Returns the message type's validator, built with `Ltix.Validator.new/1`.
  """
  @callback validator() :: Validator.t()

  @impl Ltix.Provider
  def resolve(plugins) do
    every = contributions(plugins, Ltix.Launch.EveryMessageType)
    types = contributions(plugins, __MODULE__)

    validators =
      for %Entry{module: type} = entry <- types do
        own = Validator.tag(type.validator(), type)
        {entry, build(own, contributions(plugins, type) ++ every)}
      end

    by_type = Map.new(validators, fn {entry, validator} -> {entry.module, validator} end)
    undeclared = build(%Validator{}, every)

    # Validators tag each requirement with the module that states it.
    entries =
      Map.new(
        types ++ every ++ Enum.flat_map(types, &contributions(plugins, &1.module)),
        &{&1.module, &1}
      )

    conflicts =
      Conflict.duplicates(
        types,
        &by_type[&1.module].message_type,
        &"both declare the message type #{&1}"
      ) ++
        undeclared_claims(
          [undeclared | Enum.map(validators, &elem(&1, 1))],
          PluginSet.data(plugins, Ltix.Claims),
          entries
        ) ++
        Enum.flat_map(validators, fn {_type, validator} ->
          duplicate_overrides(validator, entries)
        end)

    case conflicts do
      [] ->
        {:ok,
         %{
           message_types: Map.new(validators, fn {_type, v} -> {v.message_type, v} end),
           undeclared: undeclared
         }}

      conflicts ->
        {:error, conflicts}
    end
  end

  defp contributions(plugins, provider),
    do: Enum.uniq_by(PluginSet.entries(plugins, provider), & &1.module)

  defp build(validator, contributions) do
    Enum.reduce(contributions, validator, fn %Entry{module: contribution}, validator ->
      Validator.tag(contribution.validator(validator), contribution)
    end)
  end

  # Claims that conflict have no data, and are reported already.
  defp undeclared_claims(_validators, nil, _entries), do: []

  defp undeclared_claims(validators, %{by_name: declared}, entries) do
    for validator <- validators,
        {claim, source} <- Validator.statement_sources(validator),
        !Map.has_key?(declared, claim),
        uniq: true do
      %Conflict{
        parties: [Map.fetch!(entries, source)],
        reason: "states the claim #{inspect(claim)}, which no plugin declares"
      }
    end
  end

  defp duplicate_overrides(validator, entries) do
    overrides = Enum.uniq(Validator.override_sources(validator))

    for {claim, [_, _ | _] = sources} <- Enum.group_by(overrides, &elem(&1, 0), &elem(&1, 1)) do
      %Conflict{
        parties: Enum.map(sources, &Map.fetch!(entries, &1)),
        reason: "both override #{inspect(claim)} in #{validator.message_type}"
      }
    end
  end
end
