defmodule Ltix.Errors.Security.NonceNotFound do
  @moduledoc "Nonce not issued by this tool [Sec §5.1.3 step 9]."
  use Ltix.Errors, fields: [:spec_ref], class: :security

  def message(%{spec_ref: ref}) do
    "JWT nonce was not issued by this tool [#{ref}]"
  end
end
