defmodule Ltix.Errors.Security.TokenNotYetValid do
  @moduledoc "Token `iat` or `nbf` claim is in the future."
  use Ltix.Errors, fields: [:claim], class: :security

  def message(%{claim: claim}) do
    "JWT token is not yet valid, #{claim} is in the future"
  end
end
