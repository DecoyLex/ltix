defmodule Ltix.MembershipsService.AddScope do
  @moduledoc false
  use Ltix.ClientAssertion

  # [NRPS, Scope and Service security](https://standards.1edtech.org/lti/specifications/services/names_roles/names-role-provisioning-spec#scope-and-service-security)
  @scope "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"

  # The scope the memberships service requires.
  @doc false
  def scope, do: @scope

  @impl Ltix.Step
  def call(%{endpoints: %{Ltix.MembershipsService => _endpoint}} = assertion, _opts),
    do: {:ok, update_in(assertion.scopes, &(&1 ++ [@scope]))}

  def call(assertion, _opts), do: {:ok, assertion}
end
