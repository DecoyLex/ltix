defmodule Ltix.Claims.Check do
  @moduledoc """
  A check on the claim whose URI you pass in `:claim`.

  A check that needs only a function is an anonymous check, which a plugin adds
  with `add/2`.

      Ltix.Plugin.new(name: "My Library")
      |> Ltix.Claims.Check.add(
        claim: "https://purl.imsglobal.org/spec/lti/claim/context",
        message_types: ["LtiDeepLinkingRequest"],
        check: fn context, _claims ->
          if context.title, do: :ok, else: {:error, "must have a title"}
        end
      )

  A check that other plugins [override](`Ltix.Claims.Override`) is a module
  that implements `c:check/2`. Add it to a plugin with `Ltix.Plugin.add/2`.

      defmodule MyLibrary.ContextTitle do
        use Ltix.Claims.Check,
          claim: "https://purl.imsglobal.org/spec/lti/claim/context",
          message_types: ["LtiDeepLinkingRequest"]

        @impl Ltix.Claims.Check
        def check(%{title: nil}, _claims), do: {:error, "must have a title"}
        def check(_context, _claims), do: :ok
      end

  It runs along with the claim's other [checks](`m:Ltix.Claim#module-checks`).

  ## Options

    * `:claim` - the URI of the claim to check (required)
    * `:message_types` - the message types the check runs in, as a list of
      strings, or `:all` (defaults to `:all`)
    * `:check` - the function that checks the claim, with the arguments and
      results of `c:check/2`. Only `add/2` takes it, and requires it.
  """
  use Ltix.Provider, hook: [Ltix.Claims.Check.Declaration]

  alias Ltix.Options
  alias Ltix.Plugin
  alias Ltix.PluginSet.Entry

  @doc """
  Checks the claim's parsed value. Takes the same arguments and returns the same
  results as `c:Ltix.Claim.check/2`.
  """
  @callback check(value :: term(), claims :: %{atom() => term()}) :: :ok | {:error, term()}

  @add_schema Zoi.keyword(
                [
                  claim:
                    Zoi.string(description: "The URI of the claim to check.") |> Zoi.required(),
                  message_types:
                    Zoi.union([Zoi.literal(:all), Zoi.list(Zoi.string())],
                      description:
                        "The message types the check runs in, or `:all` for every message type."
                    )
                    |> Zoi.default(:all),
                  check:
                    Zoi.function(
                      arity: 2,
                      description:
                        "The function that checks the claim, with the arguments and results of `c:check/2`."
                    )
                    |> Zoi.required()
                ],
                unrecognized_keys: :error
              )

  @doc """
  Adds an anonymous check to a plugin.

  Raises `Ltix.Errors.Invalid.InvalidOption` for a missing, unknown, or invalid
  option.

  ## Options

  #{Zoi.describe(@add_schema)}

  ## Examples

      iex> titled = fn context, _claims ->
      ...>   if context.title, do: :ok, else: {:error, "must have a title"}
      ...> end
      iex> Ltix.Claims.Check.add(
      ...>   Ltix.Plugin.new(),
      ...>   claim: "https://purl.imsglobal.org/spec/lti/claim/context",
      ...>   check: titled
      ...> )
      %Ltix.Plugin{
        entries: [
          %Ltix.PluginSet.Entry{
            module: Ltix.Claims.Check,
            opts: [
              claim: "https://purl.imsglobal.org/spec/lti/claim/context",
              message_types: :all,
              check: titled
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
