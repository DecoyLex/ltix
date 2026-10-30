defmodule Ltix.Launch.RejectUndeclaredMessageType do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.PluginSet

  @message_type "https://purl.imsglobal.org/spec/lti/claim/message_type"

  # [Core, Message type claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#message-type-claim)
  # [DL, Message type](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#message-type)
  @impl Ltix.Step
  def call(%Ltix.Launch{claims: %{message_type: message_type}} = launch, _opts)
      when message_type != nil do
    case PluginSet.data(launch.plugins, Ltix.Launch.MessageType) do
      %{message_types: %{^message_type => _validator}} ->
        {:ok, launch}

      _undeclared ->
        {:error,
         InvalidClaim.exception(
           claim: "message_type",
           message: "unrecognized message_type",
           value: message_type
         )}
    end
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
