defmodule Ltix.Core.RequiredClaims do
  @moduledoc """
  Requires `version`, `deployment_id`, and `target_link_uri` in every message
  type, including undeclared ones.
  """

  # [Core, LTI Version claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#lti-version-claim)
  # [Core, LTI Deployment ID claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#lti-deployment-id-claim)
  # [Core, Target Link URI](https://standards.1edtech.org/lti/specifications/core/lti-spec#target-link-uri)
  use Ltix.Launch.EveryMessageType

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator) do
    defaults(validator, required: [:version, :deployment_id, :target_link_uri])
  end
end
