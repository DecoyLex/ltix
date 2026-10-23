defmodule Ltix.Errors.Security.NonceMissing do
  @moduledoc "No nonce claim in JWT."
  use Ltix.Errors, fields: [], class: :security

  def message(_error) do
    "JWT missing required nonce claim"
  end
end
