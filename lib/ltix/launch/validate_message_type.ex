defmodule Ltix.Launch.ValidateMessageType do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.Claims
  alias Ltix.Errors
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.PluginSet
  alias Ltix.Validator

  @impl Ltix.Step
  def call(%Ltix.Launch{claims: claims, plugins: plugins} = launch, _opts) do
    %{message_types: message_types, undeclared: undeclared} =
      PluginSet.data(plugins, Ltix.Launch.MessageType)

    validator = Map.get(message_types, claims.message_type, undeclared)

    # A claim at its default, `nil` or `[]` for `roles`, is missing unless the
    # platform sent it and its declaration has `strict: true`. A sent
    # `roles: []` is present, and `Ltix.Launch.ParseClaims` reports a malformed
    # value of a claim with `strict: true`.
    missing? = fn claim ->
      declaration = Claims.declaration(plugins, claim)
      sent? = Map.get(launch.raw, declaration.uri) not in [nil, :null]

      claims[claim] == declaration.default && !(sent? && declaration.strict)
    end

    missing =
      for claim <- Validator.missing(validator, claims, launch.private.ltix_options, missing?) do
        declaration = Claims.declaration(plugins, claim)
        MissingClaim.exception(claim: declaration.label)
      end

    with :ok <- Errors.collect(missing), do: {:ok, launch}
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Validated), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.ClaimsParsed), do: true
  def after?(Ltix.Launch.RejectUndeclaredMessageType), do: true
  def after?(_module), do: false
end
