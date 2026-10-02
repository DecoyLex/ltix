defmodule Ltix.LaunchClaims.ClaimHelpers do
  @moduledoc false

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim

  # Parses an optional claim with its schema, or omits it when malformed.
  @spec optional(Zoi.schema()) :: Zoi.schema()
  def optional(schema) do
    Zoi.any(typespec: Zoi.type_spec(Zoi.nullish(schema)))
    |> Zoi.transform({__MODULE__, :parse_optional, [schema]})
    |> Zoi.nullish()
  end

  @spec parse_optional(term(), Zoi.schema(), keyword()) :: {:ok, term()}
  def parse_optional(value, schema, _opts) do
    case Zoi.parse(schema, value) do
      {:ok, _} = parsed -> parsed
      {:error, _errors} -> {:ok, nil}
    end
  end

  @spec from_json(Zoi.schema(), term(), String.t(), String.t()) ::
          {:ok, term()} | {:error, Exception.t()}
  def from_json(schema, json, claim_prefix, spec_ref) do
    json = normalize_nulls(json)

    case Zoi.parse(schema, json) do
      {:ok, _} = ok -> ok
      {:error, errors} -> {:error, to_errors(errors, json, claim_prefix, spec_ref)}
    end
  end

  defp normalize_nulls(:null), do: nil

  defp normalize_nulls(json) when is_map(json) do
    json
    |> Map.to_list()
    |> Map.new(fn {key, value} -> {key, normalize_nulls(value)} end)
  end

  defp normalize_nulls(json) when is_list(json), do: Enum.map(json, &normalize_nulls/1)
  defp normalize_nulls(json), do: json

  defp to_errors(errors, json, claim_prefix, spec_ref) do
    errors
    |> Enum.map(&to_error(&1, json, claim_prefix, spec_ref))
    |> Ltix.Errors.to_class()
  end

  defp to_error(%{code: :required} = error, _json, claim_prefix, spec_ref) do
    MissingClaim.exception(
      claim: claim_path(claim_prefix, error.path),
      spec_ref: spec_ref
    )
  end

  defp to_error(error, json, claim_prefix, spec_ref) do
    InvalidClaim.exception(
      claim: claim_path(claim_prefix, error.path),
      value: lookup_value(json, error.path),
      message: error.message,
      spec_ref: spec_ref
    )
  end

  defp claim_path(prefix, path) do
    Enum.join([prefix | path], ".")
  end

  defp lookup_value(json, path) do
    Enum.reduce(path, json, fn
      key, value when is_atom(key) and is_map(value) ->
        Map.get(value, Atom.to_string(key), Map.get(value, key))

      index, value when is_integer(index) and is_list(value) ->
        Enum.at(value, index)

      _key, _value ->
        nil
    end)
  end
end
