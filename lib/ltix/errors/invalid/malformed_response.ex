defmodule Ltix.Errors.Invalid.MalformedResponse do
  @moduledoc "Service returned an unparseable response body."
  use Ltix.Errors, fields: [:service, :reason, :spec_ref], class: :invalid

  def message(%{service: service, reason: reason, spec_ref: ref}) do
    source = if service, do: " from #{inspect(service)}", else: ""
    reference = if ref, do: " [#{ref}]", else: ""
    "Malformed response#{source}: #{reason}#{reference}"
  end
end
