defmodule Ltix.Core.RequiredClaims do
  @moduledoc """
  Requires `version`, `deployment_id`, and `target_link_uri` in every message
  type, including undeclared ones.
  """

  # [Core §5.3.2](https://www.imsglobal.org/spec/lti/v1p3/#lti-version-claim)
  # [Core §5.3.3](https://www.imsglobal.org/spec/lti/v1p3/#lti-deployment-id-claim)
  # [Core §5.3.4](https://www.imsglobal.org/spec/lti/v1p3/#target-link-uri)
  use Ltix.Launch.EveryMessageType

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator) do
    defaults(validator, required: [:version, :deployment_id, :target_link_uri])
  end
end
