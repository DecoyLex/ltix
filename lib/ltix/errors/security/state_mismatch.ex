defmodule Ltix.Errors.Security.StateMismatch do
  @moduledoc "CSRF state doesn't match [Sec §7.3.1]."
  use Splode.Error, fields: [:spec_ref], class: :security

  def message(%{spec_ref: ref}) do
    "CSRF state mismatch [#{ref}]"
  end
end
