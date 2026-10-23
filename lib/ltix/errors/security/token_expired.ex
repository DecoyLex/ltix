defmodule Ltix.Errors.Security.TokenExpired do
  @moduledoc "Token exp claim is in the past, or iat claim is older than the maximum token age."
  use Ltix.Errors, fields: [], class: :security

  def message(_error) do
    "JWT token has expired"
  end
end
