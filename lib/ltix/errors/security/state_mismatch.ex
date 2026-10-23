defmodule Ltix.Errors.Security.StateMismatch do
  @moduledoc "CSRF state doesn't match."
  use Ltix.Errors, fields: [], class: :security

  def message(_error) do
    "CSRF state mismatch"
  end
end
