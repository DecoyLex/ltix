defmodule Ltix.Errors.Invalid.InvalidField do
  @moduledoc """
  A field given to a constructor, such as `Ltix.Registration.new/1`, is unknown, missing, or has an invalid value.

  The following fields of this exception are public and can be accessed freely.

    * `:field` (`t:atom/0` or `t:list/0`) - the field's name, or a list of keys for a field nested inside another, such as `[:icon, :url]`
    * `:reason` (`t:atom/0` or `t:String.t/0`) - `:unknown`, `:required`, or a description of the invalid value
  """
  use Ltix.Errors, fields: [:struct, :field, :value, :reason], class: :invalid

  alias Ltix.Errors

  def message(%{struct: struct, field: field} = error) do
    "#{inspect(struct)} field #{inspect(field)} #{description(error)}"
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
  @spec required(module(), atom() | list()) :: Exception.t()
  def required(struct, field), do: exception(struct: struct, field: field, reason: :required)

  @doc false
  @spec invalid(module(), atom() | list(), term(), String.t()) :: Exception.t()
  def invalid(struct, field, value, reason) do
    exception(struct: struct, field: field, value: value, reason: reason)
  end

  # Parses `input` with `schema`. Returns the errors for `struct`, combined
  # into one Ltix error.
  # A schema with `empty_values: [nil]` treats a field given `nil` as omitted,
  # so a required one is reported missing, and a field with a default is `nil`
  # when given `nil`.
  @doc false
  @spec parse(module(), Zoi.schema(), map()) :: {:ok, term()} | {:error, Exception.t()}
  def parse(struct, schema, input) do
    case Zoi.parse(schema, input) do
      {:ok, parsed} ->
        nils = for {key, nil} <- input, Map.has_key?(parsed, key), into: %{}, do: {key, nil}
        {:ok, Map.merge(parsed, nils)}

      {:error, errors} ->
        {:error, Errors.combine(from_zoi(struct, errors, input))}
    end
  end

  # Converts the Zoi errors from parsing `input` into errors for `struct`.
  @doc false
  @spec from_zoi(module(), [Zoi.Error.t()], map()) :: [Exception.t()]
  def from_zoi(struct, errors, input) do
    for error <- errors do
      {path, reason} = zoi_reason(error)
      {path, value} = resolve(path, input)
      exception(struct: struct, field: field_name(path), value: value, reason: reason)
    end
  end

  defp field_name([key]), do: key
  defp field_name(path), do: path

  defp zoi_reason(%Zoi.Error{code: :unrecognized_key, path: path, issue: {_, vars}}),
    do: {path ++ [Keyword.fetch!(vars, :key)], :unknown}

  defp zoi_reason(%Zoi.Error{code: :required, path: path}), do: {path, :required}
  defp zoi_reason(%Zoi.Error{path: path, message: message}), do: {path, message}

  # Returns the path with the keys the caller gave and the value at it. Zoi
  # reports unrecognized keys as strings, so keys are matched by name.
  defp resolve(path, input) do
    Enum.map_reduce(path, input, fn key, value ->
      key = input_key(key, value)
      {key, child(value, key)}
    end)
  end

  defp input_key(key, value) when is_map(value) do
    Enum.find(Map.keys(value), key, &(to_string(&1) == to_string(key)))
  end

  defp input_key(key, _value), do: key

  defp child(value, key) when is_map(value), do: Map.get(value, key)
  defp child(_value, _key), do: nil

  defp description(%{reason: :unknown}), do: "is unknown"
  defp description(%{reason: :required}), do: "is required"

  defp description(%{reason: reason, value: value}),
    do: "is invalid, #{reason} (got #{inspect(value)})"
end
