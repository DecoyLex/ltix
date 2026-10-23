defmodule Ltix.Errors.Invalid.InvalidEndpoint do
  @moduledoc "Wrong endpoint struct passed to an Advantage service."
  use Ltix.Errors, fields: [:service], class: :invalid

  def message(%{service: service}) do
    "Invalid endpoint for #{inspect(service)}"
  end
end
