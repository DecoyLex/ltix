defmodule Ltix.Errors.Security.SignatureInvalid do
  @moduledoc "JWT signature verification failed."
  use Ltix.Errors, fields: [], class: :security

  def message(_error) do
    "JWT signature verification failed"
  end
end
