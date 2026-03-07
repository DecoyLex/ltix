defmodule Ltix.Errors.Invalid.InvalidJson do
  @moduledoc "Malformed JSON or JWT structure [Cert §6.1.1]."
  use Splode.Error, fields: [:spec_ref], class: :invalid

  def message(%{spec_ref: ref}) do
    "Invalid LTI message: malformed JSON/JWT structure [#{ref}]"
  end
end
