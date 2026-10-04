defmodule Ltix.Errors.Invalid.InvalidField do
  @moduledoc """
  A field given to a constructor, such as `Ltix.Registration.new/1`, is unknown, missing, or has an invalid value.

  The following fields of this exception are public and can be accessed freely.

    * `:field` (`t:atom/0` or `t:list/0`) - the field's name, or a list of keys for a field nested inside another, such as `[:icon, :url]`
    * `:reason` (`t:atom/0` or `t:String.t/0`) - `:unknown`, `:required`, or a description of the invalid value
  """
  use Ltix.Errors, fields: [:struct, :field, :value, :reason, :spec_ref], class: :invalid

  alias Ltix.Errors

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
  @spec required(module(), atom() | list(), String.t() | nil) :: Exception.t()
  def required(struct, field, spec_ref \\ nil),
    do: exception(struct: struct, field: field, reason: :required, spec_ref: spec_ref)

  @doc false
  @spec invalid(module(), atom() | list(), term(), String.t(), String.t() | nil) :: Exception.t()
  def invalid(struct, field, value, reason, spec_ref \\ nil) do
    exception(struct: struct, field: field, value: value, reason: reason, spec_ref: spec_ref)
  end

  # Parses `input` with `schema`, returning the errors for `struct` combined
  # with `other_errors`. `spec_ref` gives the spec reference for a field. A
  # schema with `empty_values: [nil]` treats a field given `nil` as omitted, so
  # a required one is reported missing, and a field with a default is `nil`
  # when given `nil`.
  @doc false
  @spec parse(module(), Zoi.schema(), map(), (atom() | list() -> String.t()), [Exception.t()]) ::
          {:ok, term()} | {:error, Exception.t()}
  def parse(struct, schema, input, spec_ref, other_errors \\ []) do
    case {Zoi.parse(schema, input), other_errors} do
      {{:ok, parsed}, []} ->
        nils = for {key, nil} <- input, Map.has_key?(parsed, key), into: %{}, do: {key, nil}
        {:ok, Map.merge(parsed, nils)}

      {{:ok, _parsed}, _other_errors} ->
        {:error, Errors.combine(other_errors)}

      {{:error, errors}, other_errors} ->
        {:error, Errors.combine(from_zoi(struct, errors, input, spec_ref) ++ other_errors)}
    end
  end

  # Converts the Zoi errors from parsing `input` into errors for `struct`.
  # `spec_ref` gives the spec reference for a field.
  @doc false
  @spec from_zoi(module(), [Zoi.Error.t()], map(), (atom() | list() -> String.t())) ::
          [Exception.t()]
  def from_zoi(struct, errors, input, spec_ref) do
    for error <- errors do
      {path, reason} = zoi_reason(error)
      {path, value} = resolve(path, input)
      field = field_name(path)

      exception(
        struct: struct,
        field: field,
        value: value,
        reason: reason,
        spec_ref: spec_ref.(field)
      )
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
