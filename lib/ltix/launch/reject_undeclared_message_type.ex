defmodule Ltix.Launch.RejectUndeclaredMessageType do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim

  @message_types ["LtiResourceLinkRequest", "LtiDeepLinkingRequest"]
  @message_type "https://purl.imsglobal.org/spec/lti/claim/message_type"

  # [Core §5.3.1](https://www.imsglobal.org/spec/lti/v1p3/#message-type-claim)
  # [DL §4.4.2](https://www.imsglobal.org/spec/lti-dl/v2p0/#message-type)
  @impl Ltix.Step
  def call(%Ltix.Launch{claims: %{message_type: message_type}} = launch, _opts)
      when message_type in @message_types,
      do: {:ok, launch}

  def call(%Ltix.Launch{claims: %{message_type: message_type}}, _opts)
      when message_type != nil do
    {:error,
     InvalidClaim.exception(
       claim: "message_type",
       message: "unrecognized message_type",
       value: message_type
     )}
  end

  # `Ltix.Launch.ParseClaims` reports a malformed message type.
  def call(%Ltix.Launch{raw: raw} = launch, _opts) do
    if Map.get(raw, @message_type) in [nil, :null],
      do: {:error, MissingClaim.exception(claim: "message_type")},
      else: {:ok, launch}
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Validated), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.ClaimsParsed), do: true
  def after?(_module), do: false
end
