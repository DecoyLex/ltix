defmodule Ltix.Errors.Invalid.MissingParameter do
  @moduledoc "Missing OIDC login parameter."
  use Ltix.Errors, fields: [:parameter], class: :invalid

  def message(%{parameter: parameter}) do
    "Missing required OIDC parameter: #{parameter}"
  end
end
