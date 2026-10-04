defmodule Ltix.Errors.Invalid.InvalidOption do
  @moduledoc """
  An option passed to an Ltix function is unknown, missing, or has an invalid value.

  The following fields of this exception are public and can be accessed freely.

    * `:reason` (`t:atom/0` or `t:String.t/0`) - `:unknown`, `:required`, `:not_configured`, or a description of the invalid value
  """
  use Ltix.Errors, fields: [:key, :value, :reason], class: :invalid

  def message(%{key: nil, reason: reason}), do: "Options are invalid, #{reason}"
  def message(%{key: key, reason: :unknown}), do: "Option #{inspect(key)} is unknown"
  def message(%{key: key, reason: :required}), do: "Option #{inspect(key)} is required"

  def message(%{key: key, reason: :not_configured}) do
    "Option #{inspect(key)} is required. Pass it or set it in the :ltix application config."
  end

  def message(%{key: key, reason: reason}), do: "Option #{inspect(key)} is invalid, #{reason}"
end
