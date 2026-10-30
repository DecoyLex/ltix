defmodule Ltix.ResourceLinkRequest do
  @moduledoc """
  Declares the `LtiResourceLinkRequest` message type, sent when a user follows a
  resource link into the tool.

  The table below lists its own requirements. Every message type also requires
  the claims `Ltix.Core.RequiredClaims` lists.
  `Ltix.ResourceLinkRequest.NonEmptySubject` rejects an empty `subject`. Change
  what a resource link launch requires with an
  `Ltix.Launch.MessageType.Requirements`.
  """

  # [Core, Required message claims](https://standards.1edtech.org/lti/specifications/core/lti-spec#required-message-claims)
  # [Core, Anonymous launch case](https://standards.1edtech.org/lti/specifications/core/lti-spec#anonymous-launch-case)
  use Ltix.Launch.MessageType

  @impl Ltix.Launch.MessageType
  def validator do
    new("LtiResourceLinkRequest")
    |> required(:resource_link)
    |> required(:roles)
    |> required(:subject, unless: option(:allow_anonymous))
  end
end
