defmodule Ltix.Options do
  @moduledoc false

  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidOption

  # Validates options against a keyword schema that rejects unrecognized keys
  # (`unrecognized_keys: :error`), which the function head enforces. Unknown,
  # missing, and invalid options raise `InvalidOption`.
  @spec parse!(keyword(), Zoi.schema()) :: keyword()
  def parse!(opts, %Zoi.Types.Keyword{unrecognized_keys: :error} = schema) do
    case Zoi.parse(schema, opts) do
      {:ok, parsed} ->
        parsed

      {:error, errors} ->
        errors
        |> Enum.map(&invalid_option(&1, opts))
        |> Errors.combine()
        |> raise()
    end
  end

  # Returns the option, or the application environment value when the option
  # is unset. Raises `InvalidOption` when neither is set. A `nil` option
  # counts as unset.
  @spec fetch_configured!(keyword(), atom()) :: term()
  def fetch_configured!(opts, key) do
    Keyword.get(opts, key) || Application.get_env(:ltix, key) ||
      raise InvalidOption, key: key, reason: :not_configured
  end

  # Returns a parser as a function, accepting a module that exports `parse/1`
  # or a 1-arity function. Raises `InvalidOption` for `key` otherwise.
  @spec parser_function!(module() | (term() -> term()), atom()) :: (term() -> term())
  def parser_function!(parser, _key) when is_function(parser, 1), do: parser

  def parser_function!(parser, key) do
    if is_atom(parser) and Code.ensure_loaded?(parser) and function_exported?(parser, :parse, 1) do
      &parser.parse/1
    else
      raise InvalidOption,
        key: key,
        value: parser,
        reason: "parsers must be modules implementing parse/1 or 1-arity functions"
    end
  end

  # Returns a keyword list option value as a map. Other values are returned
  # unchanged.
  @spec keyword_to_map(term()) :: term()
  def keyword_to_map([]), do: %{}

  def keyword_to_map([{key, _} | _] = list) when is_atom(key) do
    if Keyword.keyword?(list), do: Map.new(list), else: list
  end

  def keyword_to_map(value), do: value

  defp invalid_option(%{code: :unrecognized_key, path: [], issue: {_, vars}}, opts) do
    key = Keyword.fetch!(vars, :key)
    InvalidOption.exception(key: key, value: Keyword.get(opts, key), reason: :unknown)
  end

  defp invalid_option(%{code: :required, path: [key]}, _opts) do
    InvalidOption.exception(key: key, reason: :required)
  end

  defp invalid_option(%{path: [key | _]} = error, opts) do
    InvalidOption.exception(key: key, value: Keyword.get(opts, key), reason: error.message)
  end

  defp invalid_option(error, opts) do
    InvalidOption.exception(value: opts, reason: error.message)
  end
end
