defmodule Ltix.Errors.Invalid.InvalidMessageType do
  @moduledoc "build_response called on a non-deep-linking launch."
  use Ltix.Errors, fields: [:message_type], class: :invalid

  # [DL, Deep linking response message](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#deep-linking-response-message)
  def message(%{message_type: message_type}) do
    "Expected LtiDeepLinkingRequest but got #{message_type}; " <>
      "build_response requires a deep linking launch"
  end
end
