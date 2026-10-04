defmodule Ltix.LaunchClaims.ClaimHelpers do
  @moduledoc false

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

  # Reads claims whose specification names differ from their struct field
  # names. Claims named like a renamed field are ignored.
  @spec rename_claims(Zoi.schema(), %{String.t() => atom()}) :: Zoi.schema()
  def rename_claims(schema, claim_names) do
    renames = Map.new(claim_names, fn {claim, field} -> {claim, Atom.to_string(field)} end)
    field_names = MapSet.new(Map.values(renames))

    Zoi.any(typespec: Zoi.type_spec(schema))
    |> Zoi.transform({__MODULE__, :parse_renamed, [schema, renames, field_names]})
  end

  @spec parse_renamed(
          term(),
          Zoi.schema(),
          %{String.t() => String.t()},
          MapSet.t(String.t()),
          keyword()
        ) :: {:ok, term()} | {:error, [Zoi.Error.t()]}
  def parse_renamed(json, schema, renames, field_names, _opts) when is_map(json) do
    renamed =
      for {key, value} <- json, not MapSet.member?(field_names, key), into: %{} do
        {Map.get(renames, key, key), value}
      end

    Zoi.parse(schema, renamed)
  end

  def parse_renamed(json, schema, _renames, _field_names, _opts), do: Zoi.parse(schema, json)

  @spec from_json(Zoi.schema(), term(), String.t() | nil, String.t()) ::
          {:ok, term()} | {:error, Exception.t()}
  def from_json(schema, json, claim_prefix, spec_ref) do
    json = normalize_nulls(json)

    case Zoi.parse(schema, json) do
      {:ok, _} = ok -> ok
      {:error, errors} -> {:error, Ltix.Errors.from_zoi(errors, json, claim_prefix, spec_ref)}
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
end
