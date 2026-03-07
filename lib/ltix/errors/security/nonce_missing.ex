defmodule Ltix.Errors.Security.NonceMissing do
  @moduledoc "No nonce claim in JWT [Sec §5.1.3 step 9]."
  use Splode.Error, fields: [:spec_ref], class: :security

  def message(%{spec_ref: ref}) do
    "JWT missing required nonce claim [#{ref}]"
  end
end
