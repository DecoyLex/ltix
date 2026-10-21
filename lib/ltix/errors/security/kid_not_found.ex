defmodule Ltix.Errors.Security.KidNotFound do
  @moduledoc "kid not found in the platform's key set [Cert §6.1.1]."
  use Ltix.Errors, fields: [:kid, :spec_ref], class: :security

  def message(%{kid: kid, spec_ref: ref}) do
    "Key not found in the platform's key set for kid: #{kid} [#{ref}]"
  end
end
