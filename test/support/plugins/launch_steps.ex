defmodule TestPlugins.ReadVerified do
  @moduledoc false
  # Sends `{:verified, launch}` to the `:pid` option's process, between
  # `Ltix.Launch.Verified` and `Ltix.Launch.ClaimsReceived`.
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, opts) do
    send(Keyword.fetch!(opts, :pid), {:verified, launch})
    {:ok, launch}
  end

  @impl Ltix.Ordered
  def after?(Ltix.Launch.Verified), do: true
  def after?(_module), do: false

  @impl Ltix.Ordered
  def before?(Ltix.Launch.ClaimsReceived), do: true
  def before?(_module), do: false
end

defmodule TestPlugins.RewriteSubject do
  @moduledoc false
  # Sets the raw `sub` claim to the `:subject` option, between
  # `Ltix.Launch.Verified` and `Ltix.Launch.ClaimsReceived`.
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, opts), do: {:ok, put_in(launch.raw["sub"], Keyword.fetch!(opts, :subject))}

  @impl Ltix.Ordered
  def after?(Ltix.Launch.Verified), do: true
  def after?(_module), do: false

  @impl Ltix.Ordered
  def before?(Ltix.Launch.ClaimsReceived), do: true
  def before?(_module), do: false
end

defmodule TestPlugins.ReadValidated do
  @moduledoc false
  # Sends `{:validated, launch}` to the `:pid` option's process, after
  # `Ltix.Launch.Validated`.
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, opts) do
    send(Keyword.fetch!(opts, :pid), {:validated, launch})
    {:ok, launch}
  end

  @impl Ltix.Ordered
  def after?(Ltix.Launch.Validated), do: true
  def after?(_module), do: false
end

defmodule TestPlugins.ReadLast do
  @moduledoc false
  # Sends `{:last, launch}` to the `:pid` option's process, after every other
  # step.
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, opts) do
    send(Keyword.fetch!(opts, :pid), {:last, launch})
    {:ok, launch}
  end

  @impl Ltix.Ordered
  def after?(_module), do: true
end

defmodule TestPlugins.BeforeValidated do
  @moduledoc false
  # A launch step that changes nothing, before `Ltix.Launch.Validated`.
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, _opts), do: {:ok, launch}

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Validated), do: true
  def before?(_module), do: false
end
