defmodule Ltix.Claims.Version do
  @moduledoc """
  The LTI version the launch follows, from the LTI version claim.
  """

  # [Core §5.3.2](https://www.imsglobal.org/spec/lti/v1p3/#lti-version-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/version",
    name: :version,
    schema: Zoi.string()
end
