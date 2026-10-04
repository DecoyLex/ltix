defmodule Ltix.Errors.Invalid.ServiceNotAvailable do
  @moduledoc """
  An Advantage service cannot be called because an endpoint or endpoint URL it needs is missing.

  The following fields of this exception are public and can be accessed freely:

    * `:reason` (`t:String.t/0` or `nil`) - what is missing
  """
  use Ltix.Errors, fields: [:service, :reason, :spec_ref], class: :invalid

  def message(%{service: service, reason: nil, spec_ref: ref}) do
    "Service not available: #{inspect(service)} [#{ref}]"
  end

  def message(%{service: service, reason: reason, spec_ref: ref}) do
    "Service not available: #{inspect(service)}. #{reason} [#{ref}]"
  end
end
