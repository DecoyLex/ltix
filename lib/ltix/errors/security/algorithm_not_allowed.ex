defmodule Ltix.Errors.Security.AlgorithmNotAllowed do
  @moduledoc "JWT alg is not RS256 [Sec §5.1.3 step 6; Sec §6.1]."
  use Splode.Error, fields: [:algorithm, :spec_ref], class: :security

  def message(%{algorithm: algorithm, spec_ref: ref}) do
    "Algorithm not allowed: #{algorithm} (only RS256 is permitted) [#{ref}]"
  end
end
