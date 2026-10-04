defmodule Ltix.Errors.Invalid.TokenRequestFailed do
  @moduledoc "OAuth token request failed."

  use Ltix.Errors,
    fields: [:error, :error_description, :status, :body, :spec_ref],
    class: :invalid

  def message(%{error: nil, status: status, spec_ref: ref}),
    do: "OAuth token request failed (HTTP #{status}) [#{ref}]"

  def message(%{error: error, error_description: description, spec_ref: ref})
      when description in [nil, ""],
      do: "OAuth token request failed: #{error} [#{ref}]"

  def message(%{error: error, error_description: description, spec_ref: ref}),
    do: "OAuth token request failed: #{error}. #{description} [#{ref}]"
end
