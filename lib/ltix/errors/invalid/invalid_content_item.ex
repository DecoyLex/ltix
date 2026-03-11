defmodule Ltix.Errors.Invalid.InvalidContentItem do
  @moduledoc "Content item field missing or invalid."
  use Splode.Error, fields: [:field, :value, :message, :spec_ref], class: :invalid

  def message(%{field: field, message: nil, value: value, spec_ref: ref}) do
    "Invalid content item field #{field}: got #{inspect(value)} [#{ref}]"
  end

  def message(%{field: field, message: message, value: _value, spec_ref: ref}) do
    "Invalid content item field #{field}: #{message} [#{ref}]"
  end
end
