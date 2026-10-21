defmodule Ltix.Extensions do
  @moduledoc false

  # Maps with caller-chosen keys, such as the custom properties of an LTI
  # resource link.

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
end
