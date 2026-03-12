defmodule Ltix.LaunchClaims.ClaimHelpers do
  @moduledoc false

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim

  @spec from_json(Zoi.schema(), map(), String.t(), String.t()) ::
          {:ok, struct()} | {:error, Exception.t()}
  def from_json(schema, json, claim_prefix, spec_ref) do
    case Zoi.parse(schema, json) do
      {:ok, _} = ok -> ok
      {:error, errors} -> {:error, to_errors(errors, json, claim_prefix, spec_ref)}
    end
  end

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
    path
    |> Enum.map(&Atom.to_string/1)
    |> Enum.reduce(json, fn key, acc ->
      if is_map(acc), do: Map.get(acc, key), else: nil
    end)
  end
end
