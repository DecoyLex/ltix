defmodule Ltix.Errors do
  @moduledoc """
  Structured error types for LTI 1.3 validation.

  Uses Splode for composable, class-based errors. There are three
  error classes, each with a default HTTP status code.

  | Class       | Status | Meaning                                                  |
  |-------------|--------|----------------------------------------------------------|
  | `:invalid`  | 400    | Spec-violating input (bad claims, missing params)        |
  | `:security` | 401    | Security framework violations (signature, nonce, expiry) |
  | `:unknown`  | 500    | Unexpected / catch-all errors                            |

  A single failure is returned directly. Several failures found
  at once are returned together in their class, such as
  `%Ltix.Errors.Invalid{errors: [...]}`.

  Use `status_code/1` to get the HTTP status for any Ltix error.

      error = Ltix.Errors.Invalid.MissingClaim.exception(claim: "sub")
      Ltix.Errors.status_code(error)
      #=> 400

  When Plug is available, all errors also implement `Plug.Exception`,
  so Phoenix error views use the correct status automatically.
  """
  use Splode,
    error_classes: [
      invalid: Ltix.Errors.Invalid,
      security: Ltix.Errors.Security,
      unknown: Ltix.Errors.Unknown
    ],
    unknown_error: Ltix.Errors.Unknown.Unknown

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim

  defmacro __using__(opts) do
    {status_code, opts} = Keyword.pop(opts, :status_code)
    {kind, opts} = Keyword.pop(opts, :type, :error)

    class = Keyword.fetch!(opts, :class)
    status = status_code || default_status(class)

    quote do
      unquote(error_definition(kind, opts))

      def __status_code__, do: unquote(status)

      if Code.ensure_loaded?(Plug) do
        defimpl Plug.Exception, for: __MODULE__ do
          def status(_), do: unquote(status)
          def actions(_), do: []
        end
      end
    end
  end

  defp error_definition(:error, opts) do
    quote do
      use Splode.Error, unquote(opts)
    end
  end

  # Splode.ErrorClass messages include every error's stack frames, so classes
  # are defined here with a message that lists only each error's message.
  defp error_definition(:error_class, opts) do
    opts = Keyword.merge(opts, fields: [errors: []], error_class?: true)

    quote do
      use Splode.Error, unquote(opts)

      @impl Exception
      def message(%{errors: errors}) do
        Enum.map_join(errors, "\n", &"* #{Exception.message(&1)}")
      end
    end
  end

  defp error_definition(other, _opts) do
    raise ArgumentError,
          "invalid :type option #{inspect(other)}. Expected :error or :error_class"
  end

  # A single failure is returned directly. Several simultaneous failures are
  # grouped in their error class.
  @doc false
  @spec combine([Exception.t(), ...]) :: Exception.t()
  def combine([error]), do: error
  def combine([_ | _] = errors), do: to_class(errors)

  # Whether `value` is an error defined by Ltix.
  @doc false
  @spec ltix_error?(term()) :: boolean()
  def ltix_error?(%module{}), do: function_exported?(module, :__status_code__, 0)
  def ltix_error?(_value), do: false

  # Returns `:ok` when every validation passed (returned `nil`), otherwise the
  # combined errors.
  @doc false
  @spec collect([Exception.t() | nil]) :: :ok | {:error, Exception.t()}
  def collect(results) do
    case Enum.reject(results, &is_nil/1) do
      [] -> :ok
      errors -> {:error, combine(errors)}
    end
  end

  # Converts the reason parsing or checking `value` failed into an error about
  # the claim, field, or property at `path`. The reason is a message, an
  # exception, or Zoi errors.
  @doc false
  @spec from_reason(term(), term(), String.t()) :: Exception.t()
  def from_reason(reason, value, path) do
    cond do
      is_list(reason) && reason != [] && Enum.all?(reason, &is_struct(&1, Zoi.Error)) ->
        from_zoi(reason, value, path)

      ltix_error?(reason) ->
        reason

      true ->
        InvalidClaim.exception(claim: path, value: value, message: property_message(reason))
    end
  end

  defp property_message(reason) when is_binary(reason), do: reason
  defp property_message(reason) when is_exception(reason), do: Exception.message(reason)
  defp property_message(reason), do: inspect(reason)

  # Converts Zoi validation errors for `input` into claim errors whose claim is
  # `prefix` (when given) followed by the path.
  @doc false
  @spec from_zoi([Zoi.Error.t(), ...], term(), String.t() | nil) :: Exception.t()
  def from_zoi(errors, input, prefix) do
    errors
    |> Enum.map(&from_zoi_error(&1, input, prefix))
    |> combine()
  end

  defp from_zoi_error(%{code: :required} = error, _input, prefix) do
    MissingClaim.exception(claim: claim_path(prefix, error.path))
  end

  defp from_zoi_error(error, input, prefix) do
    InvalidClaim.exception(
      claim: claim_path(prefix, error.path),
      value: lookup_value(input, error.path),
      message: error.message
    )
  end

  defp claim_path(nil, path), do: Enum.join(path, ".")
  defp claim_path(prefix, path), do: Enum.join([prefix | path], ".")

  defp lookup_value(input, path) do
    Enum.reduce(path, input, fn
      key, value when is_atom(key) and is_map(value) ->
        Map.get(value, Atom.to_string(key), Map.get(value, key))

      key, value when is_binary(key) and is_map(value) ->
        Map.get(value, key)

      index, value when is_integer(index) and is_list(value) ->
        Enum.at(value, index)

      _key, _value ->
        nil
    end)
  end

  defp default_status(:invalid), do: 400
  defp default_status(:security), do: 401
  defp default_status(:unknown), do: 500

  @doc """
  Returns the HTTP status code for an Ltix error.

  Each error has a status code derived from its class.

  | Class       | Default status |
  |-------------|----------------|
  | `:invalid`  | 400            |
  | `:security` | 401            |
  | `:unknown`  | 500            |

  Individual errors may override the default for their class. Exceptions
  that are not Ltix errors return 500.

  ## Examples

      iex> error = Ltix.Errors.Invalid.MissingClaim.exception(claim: "sub")
      iex> Ltix.Errors.status_code(error)
      400
  """
  @spec status_code(Exception.t()) :: pos_integer()
  def status_code(%module{} = error) do
    if ltix_error?(error), do: module.__status_code__(), else: 500
  end
end
