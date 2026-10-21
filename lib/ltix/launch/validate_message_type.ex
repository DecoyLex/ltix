defmodule Ltix.Launch.ValidateMessageType do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.PluginSet

  # [Core §5.3](https://www.imsglobal.org/spec/lti/v1p3/#required-message-claims)
  @impl Ltix.Step
  def call(%Ltix.Launch{claims: claims} = launch, _opts) do
    required =
      [:deployment_id, :target_link_uri] ++
        required(claims.message_type, launch.private.ltix_options)

    declared =
      Map.new(PluginSet.data(launch.plugins, Ltix.Claims), fn {uri, declaration} ->
        {declaration.name, Map.put(declaration, :uri, uri)}
      end)

    labels =
      for {_uri, claim} <- PluginSet.data(launch.plugins, Ltix.Claims),
          into: %{},
          do: {claim.name, claim.label}

    missing =
      for claim <- required,
          missing?(launch, declared[claim]),
          do: missing(labels[claim])

    with :ok <- Errors.collect([version(claims.version) | missing]), do: {:ok, launch}
  end

  # A claim at its default, `nil` or `[]` for `roles`, is missing unless the
  # platform sent it and its declaration has `strict: true`, so a sent
  # `roles: []` is present.
  defp missing?(launch, declaration) do
    launch.claims[declaration.name] == declaration.default &&
      (!declaration.strict || Map.get(launch.raw, declaration.uri) in [nil, :null])
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Validated), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.ClaimsParsed), do: true
  def after?(Ltix.Launch.RejectUndeclaredMessageType), do: true
  def after?(_module), do: false

  # [Core §5.3.3](https://www.imsglobal.org/spec/lti/v1p3/#lti-deployment-id-claim)
  # [Core §5.3.4](https://www.imsglobal.org/spec/lti/v1p3/#target-link-uri)
  # [Core §5.3.5](https://www.imsglobal.org/spec/lti/v1p3/#resource-link-claim)
  # [Core §5.3.6](https://www.imsglobal.org/spec/lti/v1p3/#user-identity-claims)
  # [Core §5.3.6.1](https://www.imsglobal.org/spec/lti/v1p3/#anonymous-launch-case)
  # [Core §5.3.7](https://www.imsglobal.org/spec/lti/v1p3/#roles-claim)
  defp required("LtiResourceLinkRequest", options) do
    subject = if Keyword.fetch!(options, :allow_anonymous), do: [], else: [:subject]

    [:resource_link, :roles] ++ subject
  end

  # [DL §4.4](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-request-message)
  defp required("LtiDeepLinkingRequest", _options),
    do: [:deep_linking_settings]

  defp required(_message_type, _options), do: []

  defp missing(label), do: MissingClaim.exception(claim: label)

  # [Core §5.3.2](https://www.imsglobal.org/spec/lti/v1p3/#lti-version-claim)
  defp version("1.3.0"), do: nil
  defp version(nil), do: missing("version")

  defp version(version) do
    InvalidClaim.exception(claim: "version", message: "unrecognized LTI version", value: version)
  end
end
