defmodule Ltix.ResourceLinkRequest.NonEmptySubject do
  @moduledoc """
  Core's `Ltix.Claims.Check` that rejects an empty `subject` claim in
  resource link launches.

  Other message types, such as Deep Linking requests, can have an empty
  `subject`. A plugin can replace the check with an `Ltix.Claims.Override`.
  """

  # [Core, User Identity claims](https://standards.1edtech.org/lti/specifications/core/lti-spec#user-identity-claims)
  use Ltix.Claims.Check, claim: "sub", message_types: ["LtiResourceLinkRequest"]

  @impl Ltix.Claims.Check
  def check("", _claims), do: {:error, "must be a non-empty string"}
  def check(_subject, _claims), do: :ok
end
