defmodule Ltix.Errors.Invalid.InvalidMessageType do
  @moduledoc "build_response called on a non-deep-linking launch context."
  use Splode.Error, fields: [:message_type, :spec_ref], class: :invalid

  # [DL §4.5](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-response-message)
  def message(%{message_type: mt, spec_ref: ref}) do
    "Expected LtiDeepLinkingRequest but got #{mt}; " <>
      "build_response requires a deep linking launch [#{ref}]"
  end
end
