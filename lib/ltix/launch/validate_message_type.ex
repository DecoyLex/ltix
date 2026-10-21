defmodule Ltix.Launch.ValidateMessageType do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.PluginSet
  alias Ltix.Validator

  @impl Ltix.Step
  def call(%Ltix.Launch{claims: claims, plugins: plugins} = launch, _opts) do
    %{message_types: message_types, undeclared: undeclared, claims: declared} =
      PluginSet.data(plugins, Ltix.Launch.MessageType)

    validator = Map.get(message_types, claims.message_type, undeclared)

    # A claim at its default, `nil` or `[]` for `roles`, is missing unless the
    # platform sent it and its declaration has `strict: true`. A sent
    # `roles: []` is present, and `Ltix.Launch.ParseClaims` reports a malformed
    # value of a claim with `strict: true`.
    missing? = fn claim ->
      declaration = Map.fetch!(declared, claim)

      claims[claim] == declaration.default &&
        (!declaration.strict || Map.get(launch.raw, declaration.uri) in [nil, :null])
    end

    missing =
      for claim <- Validator.missing(validator, claims, launch.private.ltix_options, missing?) do
        declaration = Map.fetch!(declared, claim)
        MissingClaim.exception(claim: declaration.label)
      end

    with :ok <- Errors.collect([version(claims.version) | missing]), do: {:ok, launch}
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Validated), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.ClaimsParsed), do: true
  def after?(Ltix.Launch.RejectUndeclaredMessageType), do: true
  def after?(_module), do: false

  # [Core §5.3.2](https://www.imsglobal.org/spec/lti/v1p3/#lti-version-claim)
  defp version(version) when version in [nil, "1.3.0"], do: nil

  defp version(version) do
    InvalidClaim.exception(claim: "version", message: "unrecognized LTI version", value: version)
  end
end
