defmodule Ltix.Errors.Security.KidMissing do
  @moduledoc "No kid in JWT header [Cert §6.1.1]."
  use Ltix.Errors, fields: [:spec_ref], class: :security

  def message(%{spec_ref: ref}) do
    "JWT header missing required kid field [#{ref}]"
  end
end
