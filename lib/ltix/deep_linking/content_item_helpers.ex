defmodule Ltix.DeepLinking.ContentItemHelpers do
  @moduledoc false

  alias Ltix.Errors.Invalid.InvalidContentItem

  @doc """
  Zoi schema for an icon or thumbnail sub-structure.
  """
  @spec icon_schema(keyword()) :: Zoi.schema()
  def icon_schema(opts \\ []) do
    Zoi.map(
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
  def window_schema(opts \\ []) do
    Zoi.map(
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
  Build a content item struct from keyword options.

  Validates against the item's schema and returns all validation errors
  at once, wrapped in `Ltix.Errors.Invalid`.
  """
  @spec new(Zoi.schema(), keyword(), atom(), String.t()) ::
          {:ok, struct()} | {:error, Exception.t()}
  def new(schema, opts, item_name, spec_ref) do
    schema =
      schema
      |> Zoi.Schema.traverse(&make_maps_accept_keywords/1)

    case Zoi.parse(schema, Map.new(opts), coerce: true) do
      {:ok, _} = ok -> ok
      {:error, errors} -> {:error, to_error(errors, item_name, spec_ref)}
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

  defp to_error(errors, item_name, spec_ref) do
    errors
    |> Enum.map(fn %{path: path, message: message} ->
      InvalidContentItem.exception(
        field: Enum.join([item_name | path], "."),
        message: message,
        spec_ref: spec_ref
      )
    end)
    |> Ltix.Errors.to_class()
  end

  # HERE BE DRAGONS
  #
  # This function rewrites Zoi's schema tree at runtime to work around two
  # separate issues. Think carefully before changing it — the interaction
  # between Zoi.Schema.traverse, union backtracking, and nested transforms
  # is subtle, and earlier attempts that looked correct broke error reporting
  # in ways that only surfaced for specific content item types.
  #
  # Zoi's map schemas only accept maps, but our public API accepts keyword
  # lists at the top level (via Map.new/1 in new/4). Without this, nested
  # map fields like `line_item` and `icon` silently drop keyword list values
  # because they never match the inner Zoi.map schema — the field parses as
  # nil with no error, and the problem only surfaces later in build_response
  # as a confusing "expected map, got nil" on a value the caller definitely
  # provided.
  #
  # The obvious fix (wrapping each map schema in a Zoi.union of the original
  # map and a keyword variant) runs into Zoi's union backtracking behavior:
  # when the winning branch's downstream transform fails (e.g. a missing
  # required field), the union retries with the next branch instead of
  # surfacing that error. This swallows field-level validation messages and
  # replaces them with a generic "expected map" type error.
  #
  # So instead we bypass Zoi's type dispatch entirely. Zoi.any() accepts the
  # value unconditionally, a first transform coerces keyword lists to maps,
  # and a second transform re-parses against the original map schema for
  # validation. No union means no backtracking, and validation errors
  # propagate with their full paths intact.
  defp make_maps_accept_keywords(%Zoi.Types.Map{} = schema) do
    Zoi.any()
    |> Zoi.transform(fn
      value when is_list(value) -> {:ok, Map.new(value)}
      other -> {:ok, other}
    end)
    |> Zoi.transform(fn value ->
      Zoi.parse(schema, value, coerce: true)
    end)
  end

  defp make_maps_accept_keywords(other), do: other
end
