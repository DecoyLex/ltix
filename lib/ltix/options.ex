defmodule Ltix.Options do
  @moduledoc false

  alias Ltix.Errors

  # Validates options against a keyword schema that rejects unrecognized keys
  # (`unrecognized_keys: :error`), which the function head enforces. Unknown,
  # missing, and invalid options raise `ArgumentError`.
  @spec parse!(keyword(), Zoi.schema()) :: keyword()
  def parse!(opts, %Zoi.Types.Keyword{unrecognized_keys: :error} = schema) do
    case Zoi.parse(schema, opts) do
      {:ok, parsed} -> parsed
      {:error, errors} -> raise ArgumentError, Enum.map_join(errors, "\n", &message/1)
    end
  end

  # Returns the option, or the application environment value when the option
  # is unset. Raises `ArgumentError` when neither is set. A `nil` option
  # counts as unset.
  @spec fetch_configured!(keyword(), atom()) :: term()
  def fetch_configured!(opts, key) do
    Keyword.get(opts, key) || Application.get_env(:ltix, key) ||
      raise ArgumentError,
            "Option #{inspect(key)} is required. Pass it or set it in the :ltix application config."
  end

  # Raises `ArgumentError` for an option with an invalid value, with the
  # reason it's invalid, such as "it must be an absolute HTTPS URL".
  @spec invalid!(atom(), String.t()) :: no_return()
  def invalid!(key, reason),
    do: raise(ArgumentError, "Option #{inspect(key)} is invalid, #{reason}")

  # Returns a keyword list option value as a map. Other values are returned
  # unchanged.
  @spec keyword_to_map(term()) :: term()
  def keyword_to_map([]), do: %{}

  def keyword_to_map([{key, _} | _] = list) when is_atom(key) do
    if Keyword.keyword?(list), do: Map.new(list), else: list
  end

  def keyword_to_map(value), do: value

  defp message(%{code: :unrecognized_key, path: [], issue: {_, vars}}),
    do: "Option #{inspect(Keyword.fetch!(vars, :key))} is unknown"

  defp message(%{code: :required, path: [key]}), do: "Option #{inspect(key)} is required"

  defp message(%{path: [key | _]} = error),
    do: "Option #{inspect(key)} is invalid, #{Errors.zoi_message(error)}"

  defp message(error), do: "Options are invalid, #{Errors.zoi_message(error)}"
end
