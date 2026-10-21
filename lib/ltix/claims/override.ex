defmodule Ltix.Claims.Override do
  @moduledoc """
  An override of a claim's check in the message types you list in
  `:message_types`.

  An override that needs only a function is an anonymous override, which a
  plugin adds with `add/2`.

      Ltix.Plugin.new(name: "My Library")
      |> Ltix.Claims.Override.add(
        check: Ltix.Claims.RoleScopeMentor,
        message_types: ["LtiSubmissionReviewRequest"],
        with: fn _subjects, _claims -> :ok end
      )

  An override can also be a module that implements `c:check/2`. Add it to a
  plugin with `Ltix.Plugin.add/2`.

      defmodule MyLibrary.MentorWithoutRole do
        use Ltix.Claims.Override,
          check: Ltix.Claims.RoleScopeMentor,
          message_types: ["LtiSubmissionReviewRequest"]

        @impl Ltix.Claims.Override
        def check(_subjects, _claims), do: :ok
      end

  The check still runs in every other message type. An override of a check that
  isn't in the plugin set does nothing. Only a check that is a module can be
  overridden.

  ## Options

    * `:check` - the module whose check the override replaces, either the module
      that declares the claim or an `Ltix.Claims.Check` (required)
    * `:message_types` - the message types the override applies in, as a list of
      strings (required)
    * `:with` - the function that checks the claim in the override's message
      types, with the arguments and results of `c:check/2`. Only `add/2` takes
      it, and requires it.
  """
  use Ltix.Provider, hook: [Ltix.Claims.Override.Declaration]

  alias Ltix.Options
  alias Ltix.Plugin
  alias Ltix.PluginSet.Entry

  @doc """
  Checks the claim's parsed value in the override's message types. Takes the
  same arguments and returns the same results as `c:Ltix.Claim.check/2`.
  """
  @callback check(value :: term(), claims :: %{atom() => term()}) :: :ok | {:error, term()}

  @add_schema Zoi.keyword(
                [
                  check:
                    Zoi.atom(
                      description:
                        "The module whose check the override replaces, either the module that declares the claim or an `Ltix.Claims.Check`."
                    )
                    |> Zoi.required(),
                  message_types:
                    Zoi.list(Zoi.string(),
                      description: "The message types the override applies in."
                    )
                    |> Zoi.min(1)
                    |> Zoi.required(),
                  with:
                    Zoi.function(
                      arity: 2,
                      description:
                        "The function that checks the claim in the override's message types, with the arguments and results of `c:check/2`."
                    )
                    |> Zoi.required()
                ],
                unrecognized_keys: :error
              )

  @doc """
  Adds an anonymous override to a plugin.

  Raises `Ltix.Errors.Invalid.InvalidOption` for a missing, unknown, or invalid
  option.

  ## Options

  #{Zoi.describe(@add_schema)}

  ## Examples

      iex> allow_any = fn _subjects, _claims -> :ok end
      iex> Ltix.Claims.Override.add(
      ...>   Ltix.Plugin.new(),
      ...>   check: Ltix.Claims.RoleScopeMentor,
      ...>   message_types: ["LtiSubmissionReviewRequest"],
      ...>   with: allow_any
      ...> )
      %Ltix.Plugin{
        entries: [
          %Ltix.PluginSet.Entry{
            module: Ltix.Claims.Override,
            opts: [
              check: Ltix.Claims.RoleScopeMentor,
              message_types: ["LtiSubmissionReviewRequest"],
              with: allow_any
            ]
          }
        ]
      }
  """
  @spec add(Plugin.t(), keyword()) :: Plugin.t()
  def add(%Plugin{} = plugin, opts) do
    opts = Options.parse!(opts, @add_schema)

    Plugin.add_entry(plugin, %Entry{module: __MODULE__, opts: opts})
  end
end
