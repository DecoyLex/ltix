defmodule Ltix.ClientAssertion do
  @moduledoc """
  The client assertion of an access token request. Client assertion steps add
  scopes and claims to it.

  Steps run before each token request. With `require_all_scopes: true`, they
  also run when Ltix checks that an existing token has every scope it needs,
  and no request follows. A step can run without a token request, so it should
  only build the assertion.

  A module becomes a client assertion step with `use Ltix.ClientAssertion`. A
  plugin adds it with `Ltix.Plugin.add/2`, or adds a function as a step with
  `add_step/2`.

  ```elixir
  defmodule MyApp.AttendanceScope do
    use Ltix.ClientAssertion

    @scope "https://lms.example.com/scope/attendance.readonly"

    @impl Ltix.Step
    def call(%{endpoints: %{MyApp.AttendanceService => _endpoint}} = assertion, _opts) do
      {:ok, update_in(assertion.scopes, &(&1 ++ [@scope]))}
    end

    def call(assertion, _opts), do: {:ok, assertion}
  end
  ```

  ## Fields

    * `:endpoints` - the endpoints of the services the token is for, keyed by
      service module
    * `:scopes` - the scopes to request. Ltix's own steps add the scopes of
      `Ltix.GradeService` and `Ltix.MembershipsService` endpoints, and Ltix
      drops duplicates.
    * `:claims` - claims that steps add to the assertion, keyed by claim name.
      Ltix sets `iss`, `aud`, the deployment ID, and the other claims a client
      assertion requires, replacing a step's claims of the same name.
    * `:errors` - errors from steps (see `Ltix.Step`). With errors, the calling
      function returns them and requests no token.
    * `:plugins` - the `Ltix.PluginSet` the steps run with
  """
  # [Sec §4.1.1](https://www.imsglobal.org/spec/security/v1p0/#using-json-web-tokens-with-oauth-2-0-client-credentials-grant)
  use Ltix.Provider, hook: [Ltix.Step, Ltix.Ordered]

  defstruct endpoints: %{}, scopes: [], claims: %{}, errors: [], plugins: nil

  @type t :: %__MODULE__{
          endpoints: %{module() => term()},
          scopes: [String.t()],
          claims: %{String.t() => term()},
          errors: [Exception.t()],
          plugins: Ltix.PluginSet.t() | nil
        }

  @doc """
  Adds an anonymous client assertion step to a plugin, a function that
  receives the client assertion and returns what `c:Ltix.Step.call/2` returns.

  ```elixir
  Ltix.Plugin.new(name: "My Library")
  |> Ltix.ClientAssertion.add_step(fn assertion ->
    {:ok, put_in(assertion.claims["https://lms.example.com/claim/tenant"], "acme")}
  end)
  ```

  Raises `ArgumentError` when `fun` doesn't take one argument.
  """
  @spec add_step(Ltix.Plugin.t(), (t() ->
                                     {:ok, t()} | {:error, Exception.t()} | {:halt, Exception.t()})) ::
          Ltix.Plugin.t()
  def add_step(plugin, fun), do: Ltix.Step.add(plugin, __MODULE__, fun)

  @doc """
  Calls `fun` with a plugin, and orders each client assertion step that `fun`
  adds after `module`.

  [Order the steps a plugin adds](`m:Ltix.Ordered#module-order-the-steps-a-plugin-adds`)
  explains how the order applies. Raises `ArgumentError` when `fun` doesn't
  return the plugin it receives with only client assertion steps added.
  """
  @spec run_after(Ltix.Plugin.t(), module(), (Ltix.Plugin.t() -> Ltix.Plugin.t())) ::
          Ltix.Plugin.t()
  def run_after(plugin, module, fun), do: Ltix.Ordered.run_after(plugin, __MODULE__, module, fun)

  @doc """
  Calls `fun` with a plugin, and orders each client assertion step that `fun`
  adds before `module`.

  Works like `run_after/3`.
  """
  @spec run_before(Ltix.Plugin.t(), module(), (Ltix.Plugin.t() -> Ltix.Plugin.t())) ::
          Ltix.Plugin.t()
  def run_before(plugin, module, fun),
    do: Ltix.Ordered.run_before(plugin, __MODULE__, module, fun)
end
