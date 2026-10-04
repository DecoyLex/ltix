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

  # Returns the option, falling back to the application environment. Raises
  # `InvalidOption` when neither is set.
  @spec fetch_configured!(keyword(), atom()) :: term()
  def fetch_configured!(opts, key) do
    Keyword.get_lazy(opts, key, fn -> Application.get_env(:ltix, key) end) ||
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
