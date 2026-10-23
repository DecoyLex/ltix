defmodule Ltix.Errors.Security.NonceReused do
  @moduledoc "Nonce previously seen, a replay attack."
  use Ltix.Errors, fields: [], class: :security

  def message(_error) do
    "JWT nonce has already been used"
  end
end
