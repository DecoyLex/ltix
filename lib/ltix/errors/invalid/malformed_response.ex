defmodule Ltix.Errors.Invalid.MalformedResponse do
  @moduledoc "Service returned an unparseable response body."
  use Splode.Error, fields: [:service, :reason, :spec_ref], class: :invalid

  def message(%{service: service, reason: reason, spec_ref: ref}) do
    "Malformed response from #{inspect(service)}: #{reason} [#{ref}]"
  end
end
