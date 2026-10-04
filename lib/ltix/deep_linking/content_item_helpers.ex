defmodule Ltix.DeepLinking.ContentItemHelpers do
  @moduledoc false

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Extensions
  alias Ltix.Options

  @not_a_map "invalid type: expected a map or keyword list"

  @doc """
  Zoi schema for a nested object option that rejects unknown keys and leaves
  out fields given `nil`.
  """
  @spec object(map(), keyword()) :: Zoi.schema()
  def object(fields, opts \\ []) do
    Zoi.map(
      fields,
      Keyword.merge(opts, unrecognized_keys: :error, empty_values: [nil], error: @not_a_map)
    )
  end

  @doc """
  Zoi schema for vendor-specific extension properties.
  """
  @spec extensions_schema() :: Zoi.schema()
  def extensions_schema, do: Extensions.schema("Vendor-specific extension properties.")

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

  Validates against the item's schema, which must reject unknown keys and treat
  `nil` as empty. Nested options may be keyword lists. A single invalid field
  returns its error, and several are grouped in `Ltix.Errors.Invalid`.
  """
  @spec new(Zoi.schema(), keyword() | map(), String.t()) ::
          {:ok, struct()} | {:error, Exception.t()}
  def new(
        %Zoi.Types.Struct{module: module, unrecognized_keys: :error, empty_values: [nil]} =
          schema,
        fields,
        spec_ref
      )
      when is_list(fields) or is_map(fields) do
    fields = Map.new(fields, fn {key, value} -> {key, Options.keyword_to_map(value)} end)

    # [DL §3.6](https://www.imsglobal.org/spec/lti-dl/v2p0/#extending-a-type)
    conflicts =
      Extensions.conflicts(module, fields[:extensions], standard_keys(module), spec_ref)

    InvalidField.parse(module, schema, fields, fn _field -> spec_ref end, conflicts)
  end

  @doc """
  Serialize a content item struct to a JSON map with camelCase keys.

  `nil` fields are omitted, including nested ones. Caller-chosen keys, such as
  those of `custom`, are not camelized. Standard fields take precedence over
  extensions with the same key.
  """
  @spec to_map(struct(), String.t()) :: map()
  def to_map(%{extensions: extensions} = item, item_type) do
    standard =
      for {field, value} <- Map.from_struct(item),
          field != :extensions and value != nil,
          into: %{"type" => item_type},
          do: {camelize(field), to_json(value)}

    Extensions.merge(standard, extensions)
  end

  defp to_json(%DateTime{} = date_time), do: DateTime.to_iso8601(date_time)

  defp to_json(map) when is_map(map),
    do: for({key, value} <- map, value != nil, into: %{}, do: {json_key(key), to_json(value)})

  defp to_json(value), do: value

  defp json_key(key) when is_atom(key), do: camelize(key)
  defp json_key(key), do: key

  defp camelize(field), do: Recase.to_camel(Atom.to_string(field))

  # The JSON keys of a content item's fields.
  defp standard_keys(module) do
    for field <- Map.keys(module.__struct__()),
        field not in [:__struct__, :extensions],
        into: MapSet.new(["type"]),
        do: camelize(field)
  end
end
