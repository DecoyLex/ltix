defmodule Ltix.Errors.Invalid.MalformedResponse do
  @moduledoc "Service returned an unparseable response body."
  use Ltix.Errors, fields: [:service, :reason], class: :invalid

  def message(%{service: nil, reason: reason}), do: "Malformed response: #{reason}"

  def message(%{service: service, reason: reason}),
    do: "Malformed response from #{inspect(service)}: #{reason}"
end
