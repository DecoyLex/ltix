defmodule Ltix.Errors.Security.NonceNotFound do
  @moduledoc "Nonce not issued by this tool."
  use Ltix.Errors, fields: [], class: :security

  def message(_error) do
    "JWT nonce was not issued by this tool"
  end
end
