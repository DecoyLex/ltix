defmodule Ltix.Errors.Invalid.InvalidJSON do
  @moduledoc "Malformed JSON or JWT structure."
  use Ltix.Errors, fields: [], class: :invalid

  def message(_error) do
    "Invalid LTI message: malformed JSON/JWT structure"
  end
end
