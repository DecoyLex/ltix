defmodule Ltix.Extensions do
  @moduledoc false

  # Extension properties a caller adds to a JSON object Ltix sends, such as a
  # score, a line item, or a deep linking content item.

  alias Ltix.Errors.Invalid.InvalidField

  @doc """
  Zoi schema for a map option with caller-chosen keys, given as strings or atoms
  and converted to strings.
  """
  @spec string_keyed_map(Zoi.schema(), keyword()) :: Zoi.schema()
  def string_keyed_map(value_schema, opts) do
    key_schema =
      [Zoi.string(), Zoi.atom()]
      |> Zoi.union(error: "invalid key: expected a string or atom")
      |> Zoi.transform({__MODULE__, :key_to_string, []})

    Zoi.map(
      key_schema,
      value_schema,
      Keyword.put(opts, :error, "invalid type: expected a map or keyword list")
    )
  end

  @doc false
  def key_to_string(key, _opts), do: {:ok, to_string(key)}

  @doc """
  Zoi schema for extension properties, keyed by strings or atoms and converted
  to strings. `nil` parses to `nil`, and the default is an empty map.
  """
  @spec schema(String.t()) :: Zoi.schema()
  def schema(description) do
    Zoi.any()
    |> string_keyed_map(description: description)
    |> Zoi.nullable()
    |> Zoi.default(%{})
  end

  @doc """
  Errors for each of `extensions` that would replace one of `standard_keys`, the
  JSON keys of the fields of `module`.
  """
  @spec conflicts(module(), term(), Enumerable.t(String.t()), String.t()) :: [Exception.t()]
  def conflicts(module, extensions, standard_keys, spec_ref) when is_map(extensions) do
    for {key, value} <- extensions, to_string(key) in standard_keys do
      InvalidField.invalid(
        module,
        [:extensions, key],
        value,
        "would replace a standard field",
        spec_ref
      )
    end
  end

  def conflicts(_module, _extensions, _standard_keys, _spec_ref), do: []

  @doc """
  Adds `extensions` to a serialized JSON map. Standard fields take precedence over
  extensions with the same key.
  """
  @spec merge(map(), map() | nil) :: map()
  def merge(json, extensions), do: Map.merge(extensions || %{}, json)
end
