defmodule Ltix.Errors.Invalid.InvalidEndpoint do
  @moduledoc "Wrong endpoint struct passed to an Advantage service."
  use Splode.Error, fields: [:service, :spec_ref], class: :invalid

  def message(%{service: service, spec_ref: ref}) do
    "Invalid endpoint for #{inspect(service)} [#{ref}]"
  end
end
