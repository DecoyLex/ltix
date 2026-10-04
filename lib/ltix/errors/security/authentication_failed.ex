defmodule Ltix.Errors.Security.AuthenticationFailed do
  @moduledoc "Platform returned an authentication error response [Sec §5.1.1.5]."
  use Ltix.Errors, fields: [:error, :error_description, :error_uri, :spec_ref], class: :security

  def message(%{error: error, error_description: description, spec_ref: ref})
      when description in [nil, ""],
      do: "Platform authentication failed: #{error} [#{ref}]"

  def message(%{error: error, error_description: description, spec_ref: ref}),
    do: "Platform authentication failed: #{error} — #{description} [#{ref}]"
end
