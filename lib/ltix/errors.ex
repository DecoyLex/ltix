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
  # A group of errors takes the first class in this list that one of its
  # errors has.
  use Splode,
    error_classes: [
      security: Ltix.Errors.Security,
      invalid: Ltix.Errors.Invalid,
      unknown: Ltix.Errors.Unknown
    ],
    unknown_error: Ltix.Errors.Unknown.Unknown

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim

  # What a value of each Zoi type is called in a message. Other types are
  # called by their names, as in "a string".
  @zoi_type_names %{
    nil => "nil",
    array: "a list",
    atom: "an atom",
    date: "a Date",
    datetime: "a DateTime",
    integer: "an integer",
    iso_date: "an ISO 8601 date",
    iso_datetime: "an ISO 8601 date and time",
    iso_naive_datetime: "an ISO 8601 date and time without an offset",
    iso_time: "an ISO 8601 time",
    keyword: "a keyword list",
    map_set: "a MapSet",
    naive_datetime: "a NaiveDateTime",
    string_boolean: "a boolean string",
    time: "a Time"
  }

  # The comparison for each Zoi bound, as in "must be at least 0".
  @zoi_bounds %{
    greater_than: "greater than",
    greater_than_or_equal_to: "at least",
    less_than: "less than",
    less_than_or_equal_to: "at most",
    invalid_length: "exactly"
  }

  # Splode documents the functions it generates with its own template text,
  # which doesn't describe Ltix. These overrides keep the functions public and
  # leave them out of the docs.
  defoverridable unwrap!: 1, unwrap!: 2, traverse_errors: 2, splode_error?: 1, splode_error?: 2

  @doc false
  def unwrap!(result), do: super(result)

  @doc false
  def unwrap!(result, opts), do: super(result, opts)

  @doc false
  @impl Splode
  def traverse_errors(error_or_errors, fun), do: super(error_or_errors, fun)

  @doc false
  @impl Splode
  def splode_error?(error), do: super(error)

  @doc false
  def splode_error?(error, splode), do: super(error, splode)

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
      message: zoi_message(error)
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

  # Zoi's message for a failed check, worded to follow the name of what was
  # checked, as in "must be a string". A message a schema gives with `error:`
  # is kept as written.
  @doc false
  @spec zoi_message(Zoi.Error.t()) :: String.t()
  def zoi_message(%Zoi.Error{code: :invalid_type, issue: {_message, vars}}),
    do: "must be #{Map.get(@zoi_type_names, vars[:type], "a #{vars[:type]}")}"

  def zoi_message(%Zoi.Error{code: code, issue: {_message, vars}})
      when code in [:invalid_enum_value, :not_in_values],
      do: "must be one of #{Enum.join(vars[:values], ", ")}"

  def zoi_message(%Zoi.Error{code: :invalid_literal, issue: {_message, vars}}),
    do: "must be #{inspect(vars[:expected])}"

  def zoi_message(%Zoi.Error{code: :invalid_tuple, issue: {_message, vars}}),
    do: "must have #{quantity(vars[:expected_length], "element")}"

  def zoi_message(%Zoi.Error{code: code, issue: {_message, vars}})
      when is_map_key(@zoi_bounds, code) do
    case vars[:type] do
      :string -> "must have #{@zoi_bounds[code]} #{quantity(vars[:count], "character")}"
      :array -> "must have #{@zoi_bounds[code]} #{quantity(vars[:count], "item")}"
      _number_or_date -> "must be #{@zoi_bounds[code]} #{vars[:count]}"
    end
  end

  def zoi_message(%Zoi.Error{code: :invalid_format, message: "invalid format: " <> rest}),
    do: rest

  # Such as "invalid email format" and "invalid IPv4 address".
  def zoi_message(%Zoi.Error{code: :invalid_format, message: "invalid " <> format}),
    do: "must be a valid #{String.trim_trailing(format, " format")}"

  def zoi_message(%Zoi.Error{message: message}), do: message

  defp quantity(1, noun), do: "1 #{noun}"
  defp quantity(count, noun), do: "#{count} #{noun}s"

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
