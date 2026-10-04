defmodule Ltix.DeepLinking.ContentItemHelpers do
  @moduledoc false

  alias Ltix.Errors
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
    result = Zoi.parse(schema, fields)

    case parse_errors(result, schema.module, fields, spec_ref) ++
           extension_conflicts(schema.module, fields[:extensions], spec_ref) do
      [] -> result
      errors -> {:error, Errors.combine(errors)}
    end
  end

  @doc """
  Serialize a content item struct to a JSON map with camelCase keys.

  `nil` fields are omitted. Caller-chosen keys, such as those of `custom`, are
  kept as given. Standard fields take precedence over extensions with the same
  key.
  """
  @spec to_map(struct(), String.t()) :: map()
  def to_map(%{extensions: extensions} = item, item_type) do
    standard =
      for {field, value} <- Map.from_struct(item),
          field != :extensions and value != nil,
          into: %{"type" => item_type},
          do: {camelize(field), to_json(value)}

    Map.merge(extensions, standard)
  end

  defp to_json(map) when is_map(map), do: Map.new(map, fn {k, v} -> {json_key(k), to_json(v)} end)
  defp to_json(value), do: value

  defp json_key(key) when is_atom(key), do: camelize(key)
  defp json_key(key), do: key

  defp camelize(field), do: Recase.to_camel(Atom.to_string(field))

  defp keyword_to_map([]), do: %{}

  defp keyword_to_map([{key, _} | _] = list) when is_atom(key) do
    if Keyword.keyword?(list), do: Map.new(list), else: list
  end

  defp keyword_to_map(value), do: value

  # [DL §3.6](https://www.imsglobal.org/spec/lti-dl/v2p0/#extending-a-type)
  defp extension_conflicts(module, extensions, spec_ref) when is_map(extensions) do
    standard =
      for field <- Map.keys(module.__struct__()),
          field not in [:__struct__, :extensions],
          into: MapSet.new(["type"]),
          do: camelize(field)

    for {key, value} <- extensions, to_string(key) in standard do
      InvalidField.invalid(
        module,
        [:extensions, key],
        value,
        "would replace a standard field",
        spec_ref
      )
    end
  end

  defp extension_conflicts(_module, _extensions, _spec_ref), do: []

  defp parse_errors({:ok, _}, _module, _fields, _spec_ref), do: []

  defp parse_errors({:error, errors}, module, fields, spec_ref),
    do: InvalidField.from_zoi(module, errors, fields, fn _field -> spec_ref end)
end
