defmodule Ltix.Errors.Security.AuthenticationFailed do
  @moduledoc "Platform returned an error instead of an id_token [Sec §5.1.1.5]."
  use Ltix.Errors, fields: [:error, :error_description, :error_uri, :spec_ref], class: :security

  def message(%{error: error, error_description: desc, spec_ref: ref}) do
    base = "Platform authentication failed: #{error} [#{ref}]"
    if desc, do: "#{base} — #{desc}", else: base
  end
end
