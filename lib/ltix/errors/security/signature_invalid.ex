defmodule Ltix.Errors.Security.SignatureInvalid do
  @moduledoc "JWT signature verification failed [Sec §5.1.3 step 1]."
  use Ltix.Errors, fields: [:spec_ref], class: :security

  def message(%{spec_ref: ref}) do
    "JWT signature verification failed [#{ref}]"
  end
end
