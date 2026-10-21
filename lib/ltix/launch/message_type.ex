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

    message_types =
      Map.new(validators, fn {entry, validator} -> {entry.module, validator.message_type} end)

    # Validators tag each requirement with the module that states it.
    entries =
      Map.new(
        types ++ every ++ Enum.flat_map(types, &contributions(plugins, &1.module)),
        fn entry ->
          {entry.module, entry}
        end
      )

    undeclared = build(%Validator{}, every)
    claims = by_short_name(PluginSet.data(plugins, Ltix.Claims))

    conflicts =
      Conflict.duplicates(
        types,
        &Map.fetch!(message_types, &1.module),
        &"both declare the message type #{&1}"
      ) ++
        undeclared_claims([undeclared | Enum.map(validators, &elem(&1, 1))], claims, entries) ++
        Enum.flat_map(validators, fn {_type, validator} ->
          duplicate_overrides(validator, entries)
        end)

    case conflicts do
      [] ->
        {:ok,
         %{
           message_types: Map.new(validators, fn {_type, v} -> {v.message_type, v} end),
           undeclared: undeclared,
           claims: claims
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
  defp by_short_name(nil), do: nil

  defp by_short_name(claims),
    do: for({uri, claim} <- claims, into: %{}, do: {claim.name, Map.put(claim, :uri, uri)})

  defp undeclared_claims(_validators, nil, _entries), do: []

  defp undeclared_claims(validators, claims, entries) do
    for validator <- validators,
        {_kind, claim, _disposition, _condition, source} <- validator.requirements,
        !Map.has_key?(claims, claim),
        uniq: true do
      %Conflict{
        parties: [Map.fetch!(entries, source)],
        reason: "states the claim #{inspect(claim)}, which no plugin declares"
      }
    end
  end

  defp duplicate_overrides(validator, entries) do
    overrides =
      for {:override, claim, _disposition, _condition, source} <- validator.requirements,
          do: {claim, Map.fetch!(entries, source)}

    for {claim, sources} <- Enum.group_by(overrides, &elem(&1, 0), &elem(&1, 1)),
        conflict <-
          Conflict.duplicates(
            sources,
            fn _source -> claim end,
            &"both override #{inspect(&1)} in #{validator.message_type}"
          ),
        do: conflict
  end
end
