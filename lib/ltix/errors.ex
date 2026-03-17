defmodule Ltix.Errors do
  @moduledoc """
  Structured error types for LTI 1.3 validation.

  Uses Splode for composable, class-based errors. Three error classes,
  each with a default HTTP status code:

  | Class       | Status | Meaning                                                  |
  |-------------|--------|----------------------------------------------------------|
  | `:invalid`  | 400    | Spec-violating input (bad claims, missing params)        |
  | `:security` | 401    | Security framework violations (signature, nonce, expiry) |
  | `:unknown`  | 500    | Unexpected / catch-all errors                            |

  Use `status_code/1` to get the HTTP status for any Ltix error:

      error = Ltix.Errors.Invalid.MissingClaim.exception(claim: "sub", spec_ref: "Core §5.3")
      Ltix.Errors.status_code(error)
      #=> 400

  When Plug is available, all errors also implement `Plug.Exception`,
  so Phoenix error views pick up the correct status automatically.
  """
  use Splode,
    error_classes: [
      invalid: Ltix.Errors.Invalid,
      security: Ltix.Errors.Security,
      unknown: Ltix.Errors.Unknown
    ],
    unknown_error: Ltix.Errors.Unknown.Unknown

  defmacro __using__(opts) do
    {status_code, opts} = Keyword.pop(opts, :status_code)
    {kind, opts} = Keyword.pop(opts, :type, :error)

    macro =
      case kind do
        :error ->
          Splode.Error

        :error_class ->
          Splode.ErrorClass

        other ->
          raise ArgumentError,
                "invalid :type option #{inspect(other)} — expected :error or :error_class"
      end

    class = Keyword.fetch!(opts, :class)
    status = status_code || default_status(class)

    quote do
      use unquote(macro), unquote(opts)

      def __status_code__, do: unquote(status)

      if Code.ensure_loaded?(Plug) do
        defimpl Plug.Exception, for: __MODULE__ do
          def status(_), do: unquote(status)
          def actions(_), do: []
        end
      end
    end
  end

  defp default_status(:invalid), do: 400
  defp default_status(:security), do: 401
  defp default_status(:unknown), do: 500

  @doc """
  Returns the HTTP status code for an Ltix error.

  Each error carries a status code derived from its class:

  | Class       | Default status |
  |-------------|----------------|
  | `:invalid`  | 400            |
  | `:security` | 401            |
  | `:unknown`  | 500            |

  Individual errors may override the default for their class.

  ## Examples

      iex> error = Ltix.Errors.Invalid.MissingClaim.exception(claim: "sub", spec_ref: "Core §5.3")
      iex> Ltix.Errors.status_code(error)
      400
  """
  @spec status_code(Exception.t()) :: pos_integer()
  def status_code(%{__struct__: module}), do: module.__status_code__()
end
