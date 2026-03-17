defmodule Ltix.Errors.Invalid.MalformedResponse do
  @moduledoc "Service returned an unparseable response body."
  use Ltix.Errors, fields: [:service, :reason, :spec_ref], class: :invalid

  def message(%{service: service, reason: reason, spec_ref: ref}) when not is_nil(service) do
    "Malformed response from #{inspect(service)}: #{reason} [#{ref}]"
  end

  def message(%{reason: reason, spec_ref: ref}) when not is_nil(ref) do
    "Malformed response: #{reason} [#{ref}]"
  end

  def message(%{reason: reason}) do
    "Malformed response: #{reason}"
  end
end
