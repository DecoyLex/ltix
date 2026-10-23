defmodule Ltix.Errors.Invalid.ServiceNotAvailable do
  @moduledoc """
  An Advantage service or token request cannot be made because an endpoint it needs is missing or unsupported.

  The following fields of this exception are public and can be accessed freely.

    * `:reason` (`t:String.t/0` or `nil`) - what is missing
  """
  use Ltix.Errors, fields: [:service, :reason], class: :invalid

  def message(%{service: service, reason: nil}) do
    "Service not available: #{inspect(service)}"
  end

  def message(%{service: service, reason: reason}) do
    "Service not available: #{inspect(service)}. #{reason}"
  end
end
