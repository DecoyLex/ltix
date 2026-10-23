defmodule Ltix.Errors.Security.AlgorithmNotAllowed do
  @moduledoc "JWT alg is not RS256."
  use Ltix.Errors, fields: [:algorithm], class: :security

  def message(%{algorithm: algorithm}) do
    "Algorithm not allowed: #{algorithm} (only RS256 is permitted)"
  end
end
