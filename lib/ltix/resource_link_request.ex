defmodule Ltix.ResourceLinkRequest do
  @moduledoc """
  Declares the `LtiResourceLinkRequest` message type, sent when a user follows a
  resource link into the tool.

  The table below lists its own requirements. Every message type also requires
  the claims `Ltix.Core.RequiredClaims` lists. Change what a resource link
  launch requires with an `Ltix.Launch.MessageType.Requirements`.
  """

  # [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims)
  # [Core §5.3.6.1](https://www.imsglobal.org/spec/lti/v1p3/#anonymous-launch-case)
  use Ltix.Launch.MessageType

  @impl Ltix.Launch.MessageType
  def validator do
    new("LtiResourceLinkRequest")
    |> required(:resource_link)
    |> required(:roles)
    |> required(:subject, unless: option(:allow_anonymous))
  end
end
