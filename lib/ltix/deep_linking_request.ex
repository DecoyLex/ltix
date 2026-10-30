defmodule Ltix.DeepLinkingRequest do
  @moduledoc """
  Declares the `LtiDeepLinkingRequest` message type, sent when a user asks the
  tool for content to place in the platform.

  The table below lists its own requirements. Every message type also requires
  the claims `Ltix.Core.RequiredClaims` lists. Change what a Deep Linking
  request requires with an `Ltix.Launch.MessageType.Requirements`.
  """

  # [DL, Deep linking request message](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#deep-linking-request-message)
  use Ltix.Launch.MessageType

  @impl Ltix.Launch.MessageType
  def validator do
    new("LtiDeepLinkingRequest")
    |> required(:deep_linking_settings)
    |> optional(:roles)
  end
end
