defmodule Ltix.Errors.Invalid.InvalidMessageType do
  @moduledoc "build_response called on a non-deep-linking launch context."
  use Ltix.Errors, fields: [:message_type], class: :invalid

  # [DL §4.5](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-response-message)
  def message(%{message_type: mt}) do
    "Expected LtiDeepLinkingRequest but got #{mt}; " <>
      "build_response requires a deep linking launch"
  end
end
