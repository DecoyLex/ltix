defmodule Ltix.Plugins.LoginTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.MissingParameter
  alias Ltix.Errors.Security.NonceReused
  alias Ltix.Errors.Unknown.InvalidPluginSet
  alias Ltix.PluginSet.Conflict
  alias Ltix.PluginSet.Entry
  alias Ltix.Test.StorageAdapter
  alias TestPlugins.Modules

  alias TestPlugins.Announced
  alias TestPlugins.BeforeAbsent
  alias TestPlugins.CycleEnd
  alias TestPlugins.CycleStart
  alias TestPlugins.Dependency
  alias TestPlugins.Dependent
  alias TestPlugins.EachAfterOther
  alias TestPlugins.Early
  alias TestPlugins.EarlySetLoginHint
  alias TestPlugins.Fail
  alias TestPlugins.FailFirst
  alias TestPlugins.Init
  alias TestPlugins.Late
  alias TestPlugins.OtherAfterEach
  alias TestPlugins.OtherDependent
  alias TestPlugins.OtherTenantKey
  alias TestPlugins.Profile
  alias TestPlugins.ReadRegistration
  alias TestPlugins.Registry
  alias TestPlugins.RegistryStep
  alias TestPlugins.SelfDependent
  alias TestPlugins.Spy
  alias TestPlugins.TenantKey
  alias TestPlugins.Trace
  alias TestPlugins.UnprovidedStep

  @launch_url "https://tool.example.com/launch"

  setup context do
    platform = Ltix.Test.setup_platform!(registration: context[:registration])
    StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))
    %{params: Ltix.Test.login_params(platform)}
  end

  defp login(params, opts) do
    Ltix.handle_login(params, @launch_url, Keyword.put(opts, :storage_adapter, StorageAdapter))
  end

  defp login_hint(redirect_uri) do
    %URI{query: query} = URI.parse(redirect_uri)
    URI.decode_query(query)["login_hint"]
  end

  # A plugin name no other test uses, so the plugin set is resolved in this test.
  defp unique_name, do: inspect(make_ref())

  defp traces do
    receive do
      {:trace, label} -> [label | traces()]
    after
      0 -> []
    end
  end

  describe "enabling plugins" do
    test "a plugin enabled twice provides each module once and adds each step twice",
         %{params: params} do
      plugin =
        {Modules, name: unique_name(), add: [Registry, {Trace, label: :enabled}]}

      assert {:ok, _login} = login(params, plugins: [plugin, plugin])

      assert traces() == [:enabled, :enabled]
      assert_received {:resolved, Registry}
      refute_received {:resolved, Registry}
    end

    test "a plugin enabled bare and with [] resolves to one plugin set", %{params: params} do
      unique = {Modules, name: unique_name()}

      assert {:ok, _login} = login(params, plugins: [Announced, unique])
      assert_received {:plugin, []}

      assert {:ok, _login} = login(params, plugins: [{Announced, []}, unique])
      refute_received {:plugin, _opts}
    end

    test "enabling a module that isn't a plugin raises", %{params: params} do
      assert_raise ArgumentError,
                   "Option :plugins is invalid, TestPlugins.Trace is not a plugin",
                   fn ->
                     login(params, plugins: [Trace])
                   end
    end
  end

  describe "steps" do
    test "run in the order they declare", %{params: params} do
      assert {:ok, _login} =
               login(params,
                 plugins: [{Modules, add: [{Late, label: :late}, {Early, label: :early}]}]
               )

      assert traces() == [:early, :late]
    end

    test "that each declare running after the other run in plugin order", %{params: params} do
      assert {:ok, _login} =
               login(params,
                 plugins: [
                   {Modules,
                    add: [{EachAfterOther, label: :each}, {OtherAfterEach, label: :other}]}
                 ]
               )

      assert traces() == [:each, :other]

      assert {:ok, _login} =
               login(params,
                 plugins: [
                   {Modules,
                    add: [{OtherAfterEach, label: :other}, {EachAfterOther, label: :each}]}
                 ]
               )

      assert traces() == [:other, :each]
    end

    test "ordering against a module that isn't running has no effect", %{params: params} do
      assert {:ok, _login} =
               login(params,
                 plugins: [
                   {Modules, add: [{Trace, label: :first}, {BeforeAbsent, label: :before_absent}]}
                 ]
               )

      assert traces() == [:first, :before_absent]
    end

    test "a step ordered before every module rejects a login before Ltix looks up the registration",
         %{params: params} do
      params = %{params | "iss" => "https://unknown.example.com"}
      step = {FailFirst, result: :halt, error: "blocked"}

      assert {:error, %Ltix.Errors.Unknown.Unknown{error: "blocked"}} =
               login(params, plugins: [{Modules, add: [step]}])
    end

    test "a halt stops later steps and returns the error", %{params: params} do
      steps = [{Fail, result: :halt, error: "halted"}, {Trace, label: :after_halt}]

      assert {:error, %Ltix.Errors.Unknown.Unknown{error: "halted"}} =
               login(params, plugins: [{Modules, add: steps}])

      assert traces() == []
    end

    test "errors let later steps run and are combined", %{params: params} do
      steps = [
        {Fail, result: :error, error: "first"},
        {Trace, label: :after_error},
        {Fail, result: :error, error: "second"}
      ]

      assert {:error, %Ltix.Errors.Unknown{errors: [first, second]}} =
               login(params, plugins: [{Modules, add: steps}])

      assert %Ltix.Errors.Unknown.Unknown{error: "first"} = first
      assert %Ltix.Errors.Unknown.Unknown{error: "second"} = second
      assert traces() == [:after_error]
    end

    test "errors of several classes are combined in the class with the highest precedence",
         %{params: params} do
      invalid = MissingParameter.exception(parameter: "login_hint")
      security = NonceReused.exception()
      unknown = "storage failed"

      for {errors, class, status} <- [
            {[invalid, security], Ltix.Errors.Security, 401},
            {[unknown, security], Ltix.Errors.Security, 401},
            {[invalid, unknown], Ltix.Errors.Invalid, 400},
            {[unknown, invalid, security], Ltix.Errors.Security, 401}
          ] do
        steps = for error <- errors, do: {Fail, result: :error, error: error}

        assert {:error, %^class{errors: grouped} = error} =
                 login(params, plugins: [{Modules, add: steps}])

        assert length(grouped) == length(errors)
        assert Ltix.Errors.status_code(error) == status
      end
    end

    test "init/1 runs once each time a plugin adds the step and its result reaches every call/2",
         %{params: params} do
      first = make_ref()
      second = make_ref()
      plugins = [{Modules, add: [{Init, ref: first}, {Init, ref: second}]}]

      assert {:ok, _login} = login(params, plugins: plugins)
      assert {:ok, _login} = login(params, plugins: plugins)

      assert_received {:init, ^first}
      assert_received {:init, ^second}
      refute_received {:init, _ref}

      for _login <- 1..2 do
        assert_received {:call, {:initialized, ^first}}
        assert_received {:call, {:initialized, ^second}}
      end
    end
  end

  describe "anonymous steps" do
    test "run with the login and can halt it", %{params: params} do
      build = fn plugin ->
        Ltix.Login.add_step(plugin, fn login ->
          send(self(), {:params, login.params})
          {:halt, Ltix.Errors.Unknown.Unknown.exception(error: "anonymous")}
        end)
      end

      assert {:error, %Ltix.Errors.Unknown.Unknown{error: "anonymous"}} =
               login(params, plugins: [{Modules, build: build}])

      assert_received {:params, ^params}
    end

    test "run where run_before/3 orders them", %{params: params} do
      build = fn plugin ->
        Ltix.Login.run_before(plugin, Ltix.Login.RegistrationFound, fn plugin ->
          Ltix.Login.add_step(plugin, fn login ->
            {:ok, put_in(login.params["login_hint"], "changed")}
          end)
        end)
      end

      assert {:ok, %{redirect_uri: redirect_uri}} =
               login(params, plugins: [{Modules, build: build}])

      assert login_hint(redirect_uri) == "changed"
    end

    test "run between two steps when run_after/3 and run_before/3 nest", %{params: params} do
      build = fn plugin ->
        Ltix.Login.run_after(plugin, Early, fn plugin ->
          Ltix.Login.run_before(plugin, Late, fn plugin ->
            Ltix.Login.add_step(plugin, fn login ->
              send(self(), {:trace, :between})
              {:ok, login}
            end)
          end)
        end)
      end

      steps = [{Early, label: :early}, {Late, label: :late}]

      assert {:ok, _login} = login(params, plugins: [{Modules, add: steps, build: build}])
      assert traces() == [:early, :between, :late]
    end

    test "are never passed to other steps' before?/1 and after?/1", %{params: params} do
      build = fn plugin -> Ltix.Login.add_step(plugin, &{:ok, &1}) end

      assert {:ok, _login} =
               login(params, plugins: [{Modules, name: unique_name(), add: [Spy], build: build}])

      assert_received {:asked, Ltix.Login.RegistrationFound}
      refute_received {:asked, Ltix.Step}
    end

    test "that a function of another arity can't be added" do
      assert_raise ArgumentError,
                   ~r/^an anonymous step must be a function of one argument/,
                   fn -> Ltix.Login.add_step(Ltix.Plugin.new(), fn _login, _opts -> :ok end) end
    end
  end

  describe "run_after/3 and run_before/3" do
    test "order the step modules added inside them, along with the modules' own orders",
         %{params: params} do
      build = fn plugin ->
        plugin
        |> Ltix.Login.run_before(Trace, &Ltix.Plugin.add(&1, {Late, label: :late}))
        |> Ltix.Plugin.add({Early, label: :early})
      end

      assert {:ok, _login} =
               login(params,
                 plugins: [{Modules, add: [{Trace, label: :first}], build: build}]
               )

      assert traces() == [:early, :late, :first]
    end

    test "that contradict a step's own order return InvalidPluginSet", %{params: params} do
      build = &Ltix.Login.run_before(&1, Early, fn plugin -> Ltix.Plugin.add(plugin, Late) end)

      assert {:error, %InvalidPluginSet{} = error} =
               login(params, plugins: [{Modules, add: [Early], build: build}])

      assert Exception.message(error) ==
               "TestPlugins.Early (Modules 1.0.0) and TestPlugins.Late (Modules 1.0.0) are ordered both before and after each other"
    end

    test "that contradict each other return InvalidPluginSet listing the anonymous step",
         %{params: params} do
      build = fn plugin ->
        Ltix.Login.run_after(plugin, Early, fn plugin ->
          Ltix.Login.run_before(
            plugin,
            Early,
            &Ltix.Login.add_step(&1, fn login -> {:ok, login} end)
          )
        end)
      end

      assert {:error, %InvalidPluginSet{} = error} =
               login(params, plugins: [{Modules, add: [Early], build: build}])

      assert Exception.message(error) ==
               "TestPlugins.Early (Modules 1.0.0) and an anonymous step of Modules 1.0.0 are ordered both before and after each other"
    end

    test "that form a cycle return InvalidPluginSet", %{params: params} do
      build =
        &Ltix.Login.run_after(&1, Late, fn plugin -> Ltix.Plugin.add(plugin, BeforeAbsent) end)

      assert {:error, %InvalidPluginSet{} = error} =
               login(params, plugins: [{Modules, add: [Early, Late], build: build}])

      assert Exception.message(error) ==
               "TestPlugins.Early (Modules 1.0.0), TestPlugins.Late (Modules 1.0.0), and TestPlugins.BeforeAbsent (Modules 1.0.0) are ordered in a cycle"
    end

    test "can't add anything other than their provider's steps" do
      assert_raise ArgumentError,
                   "the function given to run_after or run_before can add only steps of Ltix.Login, and it added TestPlugins.TenantKey",
                   fn ->
                     Ltix.Login.run_after(
                       Ltix.Plugin.new(),
                       Ltix.Login.RegistrationFound,
                       &Ltix.Plugin.add(&1, TenantKey)
                     )
                   end

      assert_raise ArgumentError,
                   ~r/^the function given to run_after or run_before must return the plugin it receives/,
                   fn ->
                     Ltix.Login.run_after(
                       Ltix.Plugin.new(),
                       Ltix.Login.RegistrationFound,
                       fn _plugin -> :ok end
                     )
                   end
    end

    test "can't order against anonymous steps" do
      assert_raise ArgumentError,
                   ~r/^run_after and run_before order steps against a step module/,
                   fn ->
                     Ltix.Login.run_after(Ltix.Plugin.new(), Ltix.Step, & &1)
                   end
    end
  end

  describe "Ltix.Login.RegistrationFound" do
    @describetag registration:
                   CustomRegistration.new(
                     id: "registration-1",
                     platform_issuer: "https://lms.example.com",
                     oauth_client_id: "client-1"
                   )

    test "a step after it reads the registration", %{params: params} do
      assert {:ok, _login} = login(params, plugins: [{Modules, add: [ReadRegistration]}])

      assert_received {:registration, %Ltix.Registration{} = registration,
                       %CustomRegistration{id: "registration-1"}}

      assert registration.issuer == "https://lms.example.com"
      assert registration.client_id == "client-1"
    end

    test "a step before it reads the parameters and changes the authentication request",
         %{params: params} do
      step = {EarlySetLoginHint, pid: self(), login_hint: "changed"}

      assert {:ok, %{redirect_uri: redirect_uri}} =
               login(params, plugins: [{Modules, add: [step]}])

      assert_received {:params, ^params}
      assert login_hint(redirect_uri) == "changed"
    end
  end

  describe "dependencies" do
    test "come before the plugin that needs them, with [] options when not enabled",
         %{params: params} do
      assert {:ok, _login} = login(params, plugins: [Dependent])

      assert traces() == [{:dependency, []}, :dependent]
    end

    test "get the options they're enabled with", %{params: params} do
      assert {:ok, _login} = login(params, plugins: [Dependent, {Dependency, tier: 1}])

      assert traces() == [{:dependency, [tier: 1]}, :dependent]
    end

    test "of two plugins appear once", %{params: params} do
      assert {:ok, _login} = login(params, plugins: [Dependent, OtherDependent])

      assert traces() == [{:dependency, []}, :dependent, :other_dependent]
    end

    test "of a profile join the plugin set", %{params: params} do
      assert {:ok, _login} = login(params, plugins: [Profile])

      assert traces() == [{:dependency, []}, :dependent, :other_dependent]
    end

    test "in a cycle return InvalidPluginSet listing both plugins", %{params: params} do
      assert {:error,
              %InvalidPluginSet{conflicts: [%Conflict{parties: [CycleStart, CycleEnd]}]} = error} =
               login(params, plugins: [CycleStart])

      assert Exception.message(error) ==
               "TestPlugins.CycleStart (Cycle start 1.0.0) and TestPlugins.CycleEnd (Cycle end 2.0.0) depend on each other in a cycle"
    end

    test "that include the plugin itself return InvalidPluginSet listing it once",
         %{params: params} do
      assert {:error, %InvalidPluginSet{conflicts: [%Conflict{parties: [SelfDependent]}]} = error} =
               login(params, plugins: [SelfDependent])

      assert Exception.message(error) ==
               "TestPlugins.SelfDependent (Self dependent 1.0.0) depends on itself"
    end
  end

  describe "providers" do
    test "extending a provider no plugin provides does nothing", %{params: params} do
      assert {:ok, _login} =
               login(params, plugins: [{Modules, add: [TenantKey, RegistryStep]}])

      assert traces() == [:registry_step]
      refute_received {:resolved, Registry}
    end

    test "init/1 doesn't run for a step of a provider no plugin provides", %{params: params} do
      ref = make_ref()

      assert {:ok, _login} =
               login(params, plugins: [{Modules, add: [{UnprovidedStep, ref: ref}]}])

      refute_received {:init, ^ref}
    end

    test "a conflict from resolve/1 returns InvalidPluginSet listing both parties",
         %{params: params} do
      plugin = {Modules, add: [Registry, TenantKey, OtherTenantKey]}

      assert {:error,
              %InvalidPluginSet{
                conflicts: [
                  %Conflict{
                    parties: [%Entry{module: TenantKey}, %Entry{module: OtherTenantKey}]
                  }
                ]
              } = error} =
               login(params, plugins: [plugin])

      assert Exception.message(error) ==
               "TestPlugins.TenantKey (Modules 1.0.0) and TestPlugins.OtherTenantKey (Modules 1.0.0) both declare the key :tenant"

      assert traces() == []
    end

    test "an entry can't set an option the module's use sets" do
      assert_raise ArgumentError,
                   "TestPlugins.TenantKey sets :key with `use`, so a plugin can't add it with :key",
                   fn -> Ltix.Plugin.add(Ltix.Plugin.new(), {TenantKey, key: :other}) end
    end
  end
end
