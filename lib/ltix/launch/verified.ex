defmodule Ltix.Launch.Verified do
  @moduledoc """
  The [launch phase](`m:Ltix.Launch#module-phases`) after Ltix verifies the
  message.

  A step ordered after it runs only for a message signed with the platform's
  key, addressed to your tool, current, not seen before, and from the login
  this browser started. `:registration`, `:source_registration`, and `:raw` are
  set.

  A launch that fails a check stops before this phase, and
  `Ltix.handle_callback/3` returns the check's error.
  """
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, _opts), do: {:ok, launch}
end
