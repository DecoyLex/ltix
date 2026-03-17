defmodule Ltix.Errors.Invalid.ServiceNotAvailable do
  @moduledoc "Service not available in launch claims."
  use Ltix.Errors, fields: [:service, :spec_ref], class: :invalid

  def message(%{service: service, spec_ref: ref}) do
    "Service not available: #{inspect(service)} — no endpoint claim in launch [#{ref}]"
  end
end
