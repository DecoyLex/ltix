defmodule Ltix.Launch do
  @moduledoc """
  The verified launch that `Ltix.handle_callback/3` returns.

      {:ok, launch} = Ltix.handle_callback(params, state)

      if Ltix.Role.instructor?(launch.claims.roles),
        do: render(conn, :grading, link: launch.claims.resource_link),
        else: render(conn, :quiz, link: launch.claims.resource_link)

  ## Fields

    * `:registration` - the `Ltix.Registration` the launch was verified against
    * `:deployment` - the `Ltix.Deployment` the launch belongs to. It's `nil`
      only for a launch without a deployment ID, which a plugin can allow.
    * `:source_registration` - the record your storage adapter returned for the
      platform. `:registration` is built from it.
    * `:source_deployment` - the record your storage adapter returned for the
      deployment. `:deployment` is built from it.
    * `:claims` - the parsed claims, keyed by short name, such as `:roles`, with
      a key for every claim the launch's plugins declare. A claim the launch
      doesn't have is `nil`, or `[]` for `:roles`. `Ltix.Core` lists Core's
      claims.
    * `:raw` - every claim's JSON value, keyed by claim name, including claims
      no plugin declares
    * `:endpoints` - the endpoints of the services the platform grants, keyed by
      service, such as `Ltix.GradeService`. Read one with `get_endpoint/2`.

  ## Steps

  Launch steps run during `Ltix.handle_callback/3`. A module becomes a launch
  step with `use Ltix.Launch`. A plugin adds it with `Ltix.Plugin.add/2`, or
  adds a function as a step with `add_step/2`.

      defmodule MyApp.LaunchTenant do
        use Ltix.Launch

        @impl Ltix.Step
        def call(launch, _opts) do
          {:ok, put_in(launch.private[:my_app_tenant], launch.claims.context)}
        end

        @impl Ltix.Ordered
        def after?(Ltix.Launch.ClaimsParsed), do: true
        def after?(_module), do: false
      end

  Steps also use these fields.

    * `:private` - data that steps keep during the launch. Prefix your keys with
      your library's name.
    * `:errors` - errors from steps (see `Ltix.Step`). A launch that
      `Ltix.handle_callback/3` returns has none.
    * `:plugins` - the `Ltix.PluginSet` the launch runs with

  ## Phases

  Ltix runs these phases in this order. A step can rely on what's true after
  each phase it's ordered after, and runs before Ltix's work after each phase
  it's ordered before.

    1. `Ltix.Launch.Verified` - the message is authentic. `:registration`,
       `:source_registration`, and `:raw` are set.
    2. `Ltix.Launch.ClaimsReceived` - Ltix parses the claims after this phase.
    3. `Ltix.Launch.ClaimsParsed` - `:claims` and `:endpoints` are set.
    4. `Ltix.Launch.Validated` - the message type and the claims it requires
       are checked. Ltix looks up the deployment after this phase.
    5. `Ltix.Launch.DeploymentFound` - `:deployment` and `:source_deployment`
       are set.

  | To | Order the step |
  |---|---|
  | read the registration or `:raw` | after `Ltix.Launch.Verified` |
  | change `:raw` or add claims before Ltix parses them | after `Ltix.Launch.Verified` and before `Ltix.Launch.ClaimsReceived` |
  | read the parsed claims | after `Ltix.Launch.ClaimsParsed` |
  | read the deployment | after `Ltix.Launch.DeploymentFound` |

  ## Private data

  Ltix keeps these keys in `:private`. A step reads them after the step that
  writes them.

  | Key | Written by | Contents |
  |---|---|---|
  | `:ltix_params` | `Ltix.handle_callback/3` | The authentication response's parameters |
  | `:ltix_state` | `Ltix.handle_callback/3` | The state `Ltix.handle_login/3` returned |
  | `:ltix_storage_adapter` | `Ltix.handle_callback/3` | The storage adapter module |
  | `:ltix_storage_adapter_options` | `Ltix.handle_callback/3` | The options for the storage adapter's callbacks |
  | `:ltix_options` | `Ltix.handle_callback/3` | The call's other options, such as `:allow_anonymous` |
  | `:ltix_id_token` | A step before `Ltix.Launch.Verified` | The ID token |
  """
  use Ltix.Provider, hook: [Ltix.Step, Ltix.Ordered]

  defstruct registration: nil,
            deployment: nil,
            source_registration: nil,
            source_deployment: nil,
            claims: %{},
            raw: %{},
            endpoints: %{},
            private: %{},
            errors: [],
            plugins: nil

  @type t :: %__MODULE__{
          registration: Ltix.Registration.t() | nil,
          deployment: Ltix.Deployment.t() | nil,
          source_registration: Ltix.Registerable.t() | nil,
          source_deployment: Ltix.Deployable.t() | nil,
          claims: %{atom() => term()},
          raw: %{String.t() => term()},
          endpoints: %{module() => term()},
          private: map(),
          errors: [Exception.t()],
          plugins: Ltix.PluginSet.t() | nil
        }

  @doc """
  Returns the endpoint of `service` that the launch has, or `nil` when the
  platform didn't grant that service.

      iex> endpoint = %Ltix.GradeService.Endpoint{
      ...>   scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"],
      ...>   line_item: "https://lms.example.com/line_items/1"
      ...> }
      iex> launch = %Ltix.Launch{endpoints: %{Ltix.GradeService => endpoint}}
      iex> Ltix.Launch.get_endpoint(launch, Ltix.GradeService)
      %Ltix.GradeService.Endpoint{
        scopes: ["https://purl.imsglobal.org/spec/lti-ags/scope/score"],
        line_item: "https://lms.example.com/line_items/1"
      }
      iex> Ltix.Launch.get_endpoint(launch, Ltix.MembershipsService)
      nil
  """
  @spec get_endpoint(t(), module()) :: term() | nil
  def get_endpoint(%__MODULE__{endpoints: endpoints}, service), do: Map.get(endpoints, service)

  @doc """
  Adds an anonymous launch step to a plugin, a function that receives the
  launch and returns what `c:Ltix.Step.call/2` returns.

      Ltix.Plugin.new(name: "My Library")
      |> Ltix.Launch.run_after(Ltix.Launch.ClaimsParsed, fn plugin ->
        Ltix.Launch.add_step(plugin, &MyLibrary.record_context/1)
      end)

  Raises `ArgumentError` when `fun` doesn't take one argument.
  """
  @spec add_step(Ltix.Plugin.t(), (t() ->
                                     {:ok, t()} | {:error, Exception.t()} | {:halt, Exception.t()})) ::
          Ltix.Plugin.t()
  def add_step(plugin, fun), do: Ltix.Step.add(plugin, __MODULE__, fun)

  @doc """
  Calls `fun` with a plugin, and orders each launch step that `fun` adds after
  `module`, such as a phase.

  [Order the steps a plugin adds](`m:Ltix.Ordered#module-order-the-steps-a-plugin-adds`)
  explains how the order applies. Raises `ArgumentError` when `fun` doesn't
  return the plugin it receives with only launch steps added.
  """
  @spec run_after(Ltix.Plugin.t(), module(), (Ltix.Plugin.t() -> Ltix.Plugin.t())) ::
          Ltix.Plugin.t()
  def run_after(plugin, module, fun), do: Ltix.Ordered.run_after(plugin, __MODULE__, module, fun)

  @doc """
  Calls `fun` with a plugin, and orders each launch step that `fun` adds before
  `module`, such as a phase.

  Works like `run_after/3`.
  """
  @spec run_before(Ltix.Plugin.t(), module(), (Ltix.Plugin.t() -> Ltix.Plugin.t())) ::
          Ltix.Plugin.t()
  def run_before(plugin, module, fun),
    do: Ltix.Ordered.run_before(plugin, __MODULE__, module, fun)
end
