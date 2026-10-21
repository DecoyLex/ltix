defmodule Ltix.Records do
  @moduledoc false

  # Converts the records applications give Ltix with `Ltix.Registerable`
  # and `Ltix.Deployable`, checking what the implementation returns.

  alias Ltix.Deployable
  alias Ltix.Deployment
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Registerable
  alias Ltix.Registration

  @type kind :: :registration | :deployment

  # Returns `{:invalid, reason}` for a record that doesn't implement the
  # protocol, or whose implementation returns something other than
  # `{:ok, struct}` or `{:error, exception}`.
  @spec convert(term(), kind()) ::
          {:ok, Registration.t() | Deployment.t()}
          | {:error, Exception.t()}
          | {:invalid, String.t()}
  def convert(record, :registration),
    do: convert(record, Registerable, &Registerable.to_registration/1, Registration)

  def convert(record, :deployment),
    do: convert(record, Deployable, &Deployable.to_deployment/1, Deployment)

  # Same as `convert/2`, but raises for a record that doesn't convert. A
  # record given as option `key` raises `InvalidOption`, and one given as an
  # argument raises `ArgumentError`.
  @spec convert!(term(), kind(), atom() | nil) ::
          {:ok, Registration.t() | Deployment.t()} | {:error, Exception.t()}
  def convert!(record, kind, key \\ nil) do
    case convert(record, kind) do
      {:invalid, reason} when is_nil(key) -> raise ArgumentError, reason
      {:invalid, reason} -> raise InvalidOption, key: key, reason: reason
      result -> result
    end
  end

  defp convert(record, protocol, conversion, struct) do
    if protocol.impl_for(record) do
      case conversion.(record) do
        {:ok, %^struct{}} = converted ->
          converted

        {:error, error} = failed when is_exception(error) ->
          failed

        _other ->
          {:invalid,
           "the #{inspect(protocol)} implementation for #{describe(record)} returned " <>
             "something other than {:ok, %#{inspect(struct)}{}} or {:error, exception}"}
      end
    else
      {:invalid,
       "expected a record that implements #{inspect(protocol)}, got #{describe(record)}"}
    end
  end

  # Records can hold key material, so only their kind is described.
  defp describe(%module{}), do: inspect(module)
  defp describe(value) when is_atom(value), do: inspect(value)
  defp describe(value) when is_map(value), do: "a map"
  defp describe(value) when is_list(value), do: "a list"
  defp describe(value) when is_tuple(value), do: "a tuple"
  defp describe(value) when is_binary(value), do: "a string"
  defp describe(value) when is_number(value), do: "a number"
  defp describe(_value), do: "a value of another type"
end
