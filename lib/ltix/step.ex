defmodule Ltix.Step do
  @moduledoc """
  A behaviour for steps, the modules Ltix calls in order with a login, launch,
  client assertion, or Deep Linking response.

  `c:call/2` receives the struct and returns one of three results.

    * `{:ok, struct}` passes the struct to the next step.
    * `{:error, exception}` records the error and runs the next step.
    * `{:halt, exception}` records the error and runs no further steps.

  `Ltix.handle_login/3` returns an error when the login has errors after its
  steps run.

      defmodule MyApp.LoginTenant do
        use Ltix.Login

        @impl Ltix.Step
        def init(opts), do: Keyword.fetch!(opts, :tenant)

        @impl Ltix.Step
        def call(login, tenant) do
          {:ok, put_in(login.private[:my_app_tenant], tenant)}
        end
      end

  ## Options

  `c:init/1` runs once for each time a plugin adds the step, when the plugin set
  resolves, and every `c:call/2` receives its result.

  ## Anonymous steps

  A plugin can add a function as a step with its provider's `add_step/2`,
  such as `Ltix.Login.add_step/2`. The function receives the struct and returns
  what `c:call/2` returns. No step's `c:Ltix.Ordered.before?/1` or
  `c:Ltix.Ordered.after?/1` receives an anonymous step, so write a module for a
  step that other steps order against.
  """

  @doc """
  Prepares the options a plugin added the step with. The default returns them
  unchanged.
  """
  @callback init(opts :: term()) :: term()

  @doc """
  Receives a struct and returns `{:ok, struct}`, `{:error, exception}`, or
  `{:halt, exception}`.
  """
  @callback call(struct :: struct(), opts :: term()) ::
              {:ok, struct()} | {:error, Exception.t()} | {:halt, Exception.t()}

  alias Ltix.Plugin
  alias Ltix.PluginSet
  alias Ltix.PluginSet.Entry
  alias Ltix.Provider

  defmacro __using__(_opts) do
    quote do
      require Ltix.Behaviour

      Ltix.Behaviour.declare_once Ltix.Step do
        def init(opts), do: opts
        defoverridable init: 1
      end
    end
  end

  @doc """
  Calls each step of a struct's module with the struct, in the order of
  `Ltix.PluginSet.entries/2`, and returns the struct.

  The struct has its `Ltix.PluginSet` in `plugins` and an `errors` list. Call it
  from the function your library's users call, and check `errors` on the
  result.

      {:ok, plugins} = Ltix.PluginSet.resolve(opts[:plugins])
      report = Ltix.Step.run(%MyLibrary.Report{plugins: plugins})
  """
  @spec run(document) :: document when document: struct()
  def run(%provider{plugins: plugins, errors: _} = document) do
    plugins
    |> PluginSet.entries(provider)
    |> Enum.reduce_while(document, fn %Entry{module: step, opts: opts}, document ->
      case step.call(document, opts) do
        {:ok, document} -> {:cont, document}
        {:error, error} -> {:cont, add_error(document, error)}
        {:halt, error} -> {:halt, add_error(document, error)}
      end
    end)
  end

  defp add_error(struct, error), do: %{struct | errors: struct.errors ++ [error]}

  @doc """
  Adds an anonymous step of `provider` to a plugin.

  `fun` receives the struct and returns what `c:call/2` returns. A provider
  whose `:hook` includes `Ltix.Step` calls it from a function of its own, such
  as `Ltix.Login.add_step/2`.

      def add_step(plugin, fun), do: Ltix.Step.add(plugin, __MODULE__, fun)

  Raises `ArgumentError` when `provider` doesn't take steps, or when `fun`
  doesn't take one argument.

  ## Examples

      iex> check_tenant = fn login -> {:ok, login} end
      iex> Ltix.Step.add(Ltix.Plugin.new(), Ltix.Login, check_tenant)
      %Ltix.Plugin{
        entries: [
          %Ltix.PluginSet.Entry{module: Ltix.Step, opts: [to: Ltix.Login, call: check_tenant]}
        ]
      }
  """
  @spec add(Plugin.t(), module(), (struct() ->
                                     {:ok, struct()}
                                     | {:error, Exception.t()}
                                     | {:halt, Exception.t()})) :: Plugin.t()
  def add(%Plugin{} = plugin, provider, fun) do
    unless Provider.hook?(provider, __MODULE__) do
      raise ArgumentError,
            "#{inspect(provider)} doesn't take steps. Its `use Ltix.Provider` must include Ltix.Step in `:hook`."
    end

    unless is_function(fun, 1) do
      raise ArgumentError,
            "an anonymous step must be a function of one argument, got #{inspect(fun)}"
    end

    Plugin.add_entry(plugin, %Entry{module: __MODULE__, opts: [to: provider, call: fun]})
  end

  # Runs an anonymous step by calling its function with the struct.
  @doc false
  @spec call(struct(), keyword()) ::
          {:ok, struct()} | {:error, Exception.t()} | {:halt, Exception.t()}
  def call(struct, opts), do: Keyword.fetch!(opts, :call).(struct)
end
