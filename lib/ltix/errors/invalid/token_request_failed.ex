defmodule Ltix.Errors.Invalid.TokenRequestFailed do
  @moduledoc "OAuth token request failed."

  use Ltix.Errors,
    fields: [:error, :error_description, :status, :body, :spec_ref],
    class: :invalid

  def message(%{error: error, spec_ref: ref}) when not is_nil(error) do
    "OAuth token request failed: #{error} [#{ref}]"
  end

  def message(%{status: status, spec_ref: ref}) do
    "OAuth token request failed (HTTP #{status}) [#{ref}]"
  end
end
