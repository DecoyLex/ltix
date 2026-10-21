defmodule TestPlugins.Trace do
  @moduledoc false
  # Sends its label to the calling process. The ordered steps below call it.
  use Ltix.Login

  @impl Ltix.Step
  def call(login, opts) do
    send(self(), {:trace, Keyword.fetch!(opts, :label)})
    {:ok, login}
  end
end

defmodule TestPlugins.Early do
  @moduledoc false
  use Ltix.Login

  @impl Ltix.Step
  defdelegate call(login, opts), to: TestPlugins.Trace
end

defmodule TestPlugins.Late do
  @moduledoc false
  use Ltix.Login

  @impl Ltix.Step
  defdelegate call(login, opts), to: TestPlugins.Trace

  @impl Ltix.Ordered
  def after?(TestPlugins.Early), do: true
  def after?(_module), do: false
end

defmodule TestPlugins.EachAfterOther do
  @moduledoc false
  use Ltix.Login

  @impl Ltix.Step
  defdelegate call(login, opts), to: TestPlugins.Trace

  @impl Ltix.Ordered
  def after?(TestPlugins.OtherAfterEach), do: true
  def after?(_module), do: false
end

defmodule TestPlugins.OtherAfterEach do
  @moduledoc false
  use Ltix.Login

  @impl Ltix.Step
  defdelegate call(login, opts), to: TestPlugins.Trace

  @impl Ltix.Ordered
  def after?(TestPlugins.EachAfterOther), do: true
  def after?(_module), do: false
end

defmodule TestPlugins.Fail do
  @moduledoc false
  # Returns `{:error, e}` or `{:halt, e}`, as its `:result` option says.
  use Ltix.Login

  alias Ltix.Errors.Unknown.Unknown

  @impl Ltix.Step
  def call(_login, opts) do
    error = Unknown.exception(error: Keyword.fetch!(opts, :error))
    {Keyword.fetch!(opts, :result), error}
  end
end

defmodule TestPlugins.FailFirst do
  @moduledoc false
  # `TestPlugins.Fail`, ordered before every other step.
  use Ltix.Login

  @impl Ltix.Step
  defdelegate call(login, opts), to: TestPlugins.Fail

  @impl Ltix.Ordered
  def before?(_module), do: true
end

defmodule TestPlugins.Init do
  @moduledoc false
  # Reports when `init/1` runs and what each `call/2` receives.
  use Ltix.Login

  @impl Ltix.Step
  def init(opts) do
    ref = Keyword.fetch!(opts, :ref)
    send(self(), {:init, ref})
    {:initialized, ref}
  end

  @impl Ltix.Step
  def call(login, initialized) do
    send(self(), {:call, initialized})
    {:ok, login}
  end
end

defmodule TestPlugins.BeforeAbsent do
  @moduledoc false
  use Ltix.Login

  @impl Ltix.Step
  defdelegate call(login, opts), to: TestPlugins.Trace

  @impl Ltix.Ordered
  def before?(TestPlugins.Early), do: true
  def before?(_module), do: false
end

defmodule TestPlugins.Announced do
  @moduledoc false
  # Sends `{:plugin, opts}` when Ltix calls its `plugin/1`.
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(opts) do
    send(self(), {:plugin, opts})
    Ltix.Plugin.new(name: "Announced")
  end
end

defmodule TestPlugins.ReadRegistration do
  @moduledoc false
  # Sends `{:registration, registration, source_registration}` from the login to
  # the calling process, after `Ltix.Login.RegistrationFound`.
  use Ltix.Login

  @impl Ltix.Step
  def call(login, _opts) do
    send(self(), {:registration, login.registration, login.source_registration})
    {:ok, login}
  end

  @impl Ltix.Ordered
  def after?(Ltix.Login.RegistrationFound), do: true
  def after?(_module), do: false
end

defmodule TestPlugins.EarlySetLoginHint do
  @moduledoc false
  # Sends `{:params, params}` from the login to the `:pid` option's process, and
  # sets the login hint to the `:login_hint` option, before
  # `Ltix.Login.RegistrationFound`.
  use Ltix.Login

  @impl Ltix.Step
  def call(login, opts) do
    send(Keyword.fetch!(opts, :pid), {:params, login.params})
    {:ok, put_in(login.params["login_hint"], Keyword.fetch!(opts, :login_hint))}
  end

  @impl Ltix.Ordered
  def before?(Ltix.Login.RegistrationFound), do: true
  def before?(_module), do: false
end

defmodule TestPlugins.Spy do
  @moduledoc false
  # Sends `{:asked, module}` for each module its `before?/1` and `after?/1`
  # receive, and declares no order.
  use Ltix.Login

  @impl Ltix.Step
  def call(login, _opts), do: {:ok, login}

  @impl Ltix.Ordered
  def before?(module) do
    send(self(), {:asked, module})
    false
  end

  @impl Ltix.Ordered
  def after?(module) do
    send(self(), {:asked, module})
    false
  end
end
