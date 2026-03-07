defmodule Ltix.Errors.Invalid.MissingParameter do
  @moduledoc "Missing OIDC login parameter [Sec §5.1.1.1]."
  use Splode.Error, fields: [:parameter, :spec_ref], class: :invalid

  def message(%{parameter: parameter, spec_ref: ref}) do
    "Missing required OIDC parameter: #{parameter} [#{ref}]"
  end
end
