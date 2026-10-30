defmodule Ltix.Login do
  @moduledoc """
  The login request that login steps read and change during
  `Ltix.handle_login/3`.

  A login step can reject a login before the user goes to the platform, such
  as a login for a suspended tenant. A module becomes a login step with
  `use Ltix.Login`. A plugin adds it with `Ltix.Plugin.add/2`, or adds a
  function as a step with `add_step/2`.

  ```elixir
  defmodule MyApp.RejectSuspendedTenant do
    use Ltix.Login

    @impl Ltix.Step
    def call(login, _opts) do
      tenant_id = login.source_registration.tenant_id

      if MyApp.Tenants.suspended?(tenant_id),
        do: {:halt, MyApp.TenantSuspended.exception(tenant_id: tenant_id)},
        else: {:ok, login}
    end

    @impl Ltix.Ordered
    def after?(Ltix.Login.RegistrationFound), do: true
    def after?(_module), do: false
  end
  ```

  ## Fields

    * `:params` - the login request's parameters
    * `:registration` - the `Ltix.Registration` of the platform that sent the
      login
    * `:source_registration` - the record your storage adapter returned for the
      platform. `:registration` is built from it. Steps ordered after
      `Ltix.Login.RegistrationFound` can read both.
    * `:private` - data that steps keep during the login. Prefix your keys with
      your library's name.
    * `:errors` - errors from steps (see `Ltix.Step`). A login with errors makes
      `Ltix.handle_login/3` return an error.
    * `:plugins` - the `Ltix.PluginSet` the login runs with

  ## Phases

  Ltix checks the parameters and looks up the registration before this phase,
  and builds the authentication request after it.

    * `Ltix.Login.RegistrationFound` - the parameters are checked, and
      `:registration` and `:source_registration` are set.

  | To | Order the step |
  |---|---|
  | reject a login from its parameters before Ltix looks up the registration | before every module, with `def before?(_module), do: true` |
  | read the registration | after `Ltix.Login.RegistrationFound` |
  """
  use Ltix.Provider, hook: [Ltix.Step, Ltix.Ordered]

  defstruct params: %{},
            registration: nil,
            source_registration: nil,
            private: %{},
            errors: [],
            plugins: nil

  @type t :: %__MODULE__{
          params: map(),
          registration: Ltix.Registration.t() | nil,
          source_registration: Ltix.Registerable.t() | nil,
          private: map(),
          errors: [Exception.t()],
          plugins: Ltix.PluginSet.t() | nil
        }

  @doc """
  Adds an anonymous login step to a plugin, a function that receives the login
  and returns what `c:Ltix.Step.call/2` returns.

  ```elixir
  Ltix.Plugin.new(name: "My Library")
  |> Ltix.Login.add_step(fn login ->
    {:ok, put_in(login.private[:my_library_started_at], DateTime.utc_now())}
  end)
  ```

  Raises `ArgumentError` when `fun` doesn't take one argument.

  ## Examples

  ```elixir
  iex> check_tenant = fn login -> {:ok, login} end
  iex> Ltix.Login.add_step(Ltix.Plugin.new(), check_tenant)
  %Ltix.Plugin{
    entries: [
      %Ltix.PluginSet.Entry{module: Ltix.Step, opts: [to: Ltix.Login, call: check_tenant]}
    ]
  }
  ```
  """
  @spec add_step(Ltix.Plugin.t(), (t() ->
                                     {:ok, t()} | {:error, Exception.t()} | {:halt, Exception.t()})) ::
          Ltix.Plugin.t()
  def add_step(plugin, fun), do: Ltix.Step.add(plugin, __MODULE__, fun)

  @doc """
  Calls `fun` with a plugin, and orders each login step that `fun` adds after
  `module`, such as a phase.

  ```elixir
  Ltix.Plugin.new(name: "My Library")
  |> Ltix.Login.run_after(Ltix.Login.RegistrationFound, fn plugin ->
    Ltix.Login.add_step(plugin, &MyLibrary.reject_suspended_tenant/1)
  end)
  ```

  [Order the steps a plugin adds](`m:Ltix.Ordered#module-order-the-steps-a-plugin-adds`)
  explains how the order applies.
  Raises `ArgumentError` when `fun` doesn't return the plugin it receives with
  only login steps added.
  """
  @spec run_after(Ltix.Plugin.t(), module(), (Ltix.Plugin.t() -> Ltix.Plugin.t())) ::
          Ltix.Plugin.t()
  def run_after(plugin, module, fun), do: Ltix.Ordered.run_after(plugin, __MODULE__, module, fun)

  @doc """
  Calls `fun` with a plugin, and orders each login step that `fun` adds before
  `module`, such as a phase.

  Works like `run_after/3`.
  """
  @spec run_before(Ltix.Plugin.t(), module(), (Ltix.Plugin.t() -> Ltix.Plugin.t())) ::
          Ltix.Plugin.t()
  def run_before(plugin, module, fun),
    do: Ltix.Ordered.run_before(plugin, __MODULE__, module, fun)
end
