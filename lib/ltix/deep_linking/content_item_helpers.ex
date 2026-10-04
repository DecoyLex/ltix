defmodule Ltix.DeepLinking.ContentItemHelpers do
  @moduledoc false

  alias Ltix.Errors.Invalid.InvalidField

  @not_a_map "invalid type: expected a map or keyword list"

  @doc """
  Zoi schema for a nested object option that rejects unknown keys.
  """
  @spec object(map(), keyword()) :: Zoi.schema()
  def object(fields, opts \\ []) do
    Zoi.map(fields, Keyword.merge(opts, unrecognized_keys: :error, error: @not_a_map))
  end

  @doc """
  Zoi schema for a map option with caller-chosen keys, given as strings or atoms
  and kept as strings.
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
      Keyword.put(opts, :error, @not_a_map)
    )
  end

  @doc false
  def key_to_string(key, _opts), do: {:ok, to_string(key)}

  @doc """
  Zoi schema for vendor-specific extension properties.
  """
  @spec extensions_schema() :: Zoi.schema()
  def extensions_schema do
    Zoi.any()
    |> string_keyed_map(description: "Vendor-specific extension properties.")
    |> Zoi.default(%{})
  end

  @doc """
  Zoi schema for an icon or thumbnail sub-structure.
  """
  @spec icon_schema(keyword()) :: Zoi.schema()
  def icon_schema(opts) do
    object(
      %{
        url: Zoi.string(description: "URL of the icon image."),
        width: Zoi.integer(description: "Width in pixels.") |> Zoi.optional(),
        height: Zoi.integer(description: "Height in pixels.") |> Zoi.optional()
      },
      opts
    )
  end

  @doc """
  Zoi schema for a window presentation sub-structure.
  """
  @spec window_schema(keyword()) :: Zoi.schema()
  def window_schema(opts) do
    object(
      %{
        target_name: Zoi.string(description: "Name of the window or tab.") |> Zoi.optional(),
        width: Zoi.integer(description: "Suggested window width in pixels.") |> Zoi.optional(),
        height: Zoi.integer(description: "Suggested window height in pixels.") |> Zoi.optional(),
        window_features:
          Zoi.string(description: "Comma-separated window features (e.g. `\"menubar=no\"`).")
          |> Zoi.optional()
      },
      opts
    )
  end

  @doc """
  Build a content item struct from a keyword list or map of fields.

  Validates against the item's schema, which must reject unknown keys. Nested
  options may be keyword lists. A single invalid field returns its error, and
  several are grouped in `Ltix.Errors.Invalid`.
  """
  @spec new(Zoi.schema(), keyword() | map(), String.t()) ::
          {:ok, struct()} | {:error, Exception.t()}
  def new(%Zoi.Types.Struct{unrecognized_keys: :error} = schema, fields, spec_ref)
      when is_list(fields) or is_map(fields) do
    fields = Map.new(fields, fn {key, value} -> {key, keyword_to_map(value)} end)

    case Zoi.parse(schema, fields) do
      {:ok, _} = ok -> ok
      {:error, errors} -> {:error, to_error(errors, schema.module, fields, spec_ref)}
    end
  end

  @doc """
  Add top-level struct fields to the JSON map, converting keys to camelCase.
  `nil` fields are omitted.
  """
  @spec put_fields(map(), struct(), [atom()]) :: map()
  def put_fields(acc, item, fields) do
    Enum.reduce(fields, acc, fn field, acc ->
      case Map.fetch!(item, field) do
        nil -> acc
        value -> Map.put(acc, camelize(field), value)
      end
    end)
  end

  @doc """
  Add a nested map (e.g. icon, window) to the JSON map, converting its
  keys to camelCase. Omitted when the value is `nil`.
  """
  @spec put_sub_map(map(), String.t(), map() | nil) :: map()
  def put_sub_map(acc, _key, nil), do: acc
  def put_sub_map(acc, key, map), do: Map.put(acc, key, serialize_map(map))

  @doc """
  Add a value to the JSON map without transforming its keys (e.g. the
  `custom` map which already has string keys). Omitted when `nil`.
  """
  @spec put_passthrough(map(), String.t(), term()) :: map()
  def put_passthrough(acc, _key, nil), do: acc
  def put_passthrough(acc, key, value), do: Map.put(acc, key, value)

  defp serialize_map(map) do
    Map.new(map, fn {k, v} -> {camelize(k), v} end)
  end

  defp camelize(atom) when is_atom(atom), do: Recase.to_camel(Atom.to_string(atom))
  defp camelize(binary) when is_binary(binary), do: Recase.to_camel(binary)

  defp keyword_to_map([]), do: %{}

  defp keyword_to_map([{key, _} | _] = list) when is_atom(key) do
    if Keyword.keyword?(list), do: Map.new(list), else: list
  end

  defp keyword_to_map(value), do: value

  defp to_error(errors, module, fields, spec_ref) do
    module
    |> InvalidField.from_zoi(errors, fields, fn _field -> spec_ref end)
    |> Ltix.Errors.combine()
  end
end
