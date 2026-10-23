defmodule Ltix.Errors.Security.KidMissing do
  @moduledoc "No kid in JWT header."
  use Ltix.Errors, fields: [], class: :security

  def message(_error) do
    "JWT header missing required kid field"
  end
end
