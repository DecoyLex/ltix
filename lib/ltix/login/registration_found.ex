defmodule Ltix.Login.RegistrationFound do
  @moduledoc """
  The [login phase](`m:Ltix.Login#module-phases`) after Ltix checks the login
  parameters and finds the registration.

  A step ordered after it can read `:params` and `:registration`, along with
  `:source_registration`, the record your storage adapter returned for the
  platform. Ltix builds the authentication request after this phase, from
  `:registration` and the `"login_hint"` and `"lti_message_hint"` parameters.

  `:errors` has only the errors that steps returned with `{:error, exception}`.
  A login with errors makes `Ltix.handle_login/3` return an error.

  The login request isn't signed, so anyone can send any parameters. Repeat a
  check that controls access in a launch step ordered after
  `Ltix.Launch.Verified`.
  """
  use Ltix.Login

  @impl Ltix.Step
  def call(login, _opts), do: {:ok, login}
end
