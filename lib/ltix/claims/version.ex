defmodule Ltix.Claims.Version do
  @moduledoc """
  The LTI version the launch follows, from the LTI version claim.

  Read it from `launch.claims.version`. Ltix rejects a version other than
  `"1.3.0"`.
  """

  # [Core, LTI Version claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#lti-version-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/version",
    name: :version,
    schema: Zoi.string()

  @impl Ltix.Claim
  def check("1.3.0", _claims), do: :ok
  def check(_version, _claims), do: {:error, "unrecognized LTI version"}
end
