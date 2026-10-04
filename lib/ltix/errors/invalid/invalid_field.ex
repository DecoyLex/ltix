defmodule Ltix.Errors.Invalid.InvalidField do
  @moduledoc """
  A field given to a constructor, such as `Ltix.Registration.new/1`, is unknown, missing, or has an invalid value.

  `struct` is the struct being built. `reason` is `:unknown`, `:required`, or a description of the invalid value.
  """
  use Ltix.Errors, fields: [:struct, :field, :value, :reason, :spec_ref], class: :invalid

  def message(%{struct: struct, field: field, spec_ref: ref} = error) do
    "#{inspect(struct)} field #{inspect(field)} #{description(error)}" <>
      if(ref, do: " [#{ref}]", else: "")
  end

  # Errors for every field of `attrs` not in `fields`.
  @doc false
  @spec unknown_fields(module(), map(), [atom()]) :: [Exception.t()]
  def unknown_fields(struct, attrs, fields) do
    for {field, value} <- attrs, field not in fields do
      exception(struct: struct, field: field, value: value, reason: :unknown)
    end
  end

  @doc false
  @spec required(module(), atom()) :: Exception.t()
  def required(struct, field), do: exception(struct: struct, field: field, reason: :required)

  @doc false
  @spec invalid(module(), atom(), term(), String.t(), String.t()) :: Exception.t()
  def invalid(struct, field, value, reason, spec_ref) do
    exception(struct: struct, field: field, value: value, reason: reason, spec_ref: spec_ref)
  end

  defp description(%{reason: :unknown}), do: "is unknown"
  defp description(%{reason: :required}), do: "is required"

  defp description(%{reason: reason, value: value}),
    do: "is invalid, #{reason} (got #{inspect(value)})"
end
