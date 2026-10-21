defmodule Ltix.MembershipsService.AddScope do
  @moduledoc false
  use Ltix.ClientAssertion

  # [NRPS §3.6.1.2](https://www.imsglobal.org/spec/lti-nrps/v2p0/#scope-for-access)
  @scope "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"

  # The scope the memberships service requires.
  @doc false
  def scope, do: @scope

  @impl Ltix.Step
  def call(%{endpoints: %{Ltix.MembershipsService => _endpoint}} = assertion, _opts),
    do: {:ok, update_in(assertion.scopes, &(&1 ++ [@scope]))}

  def call(assertion, _opts), do: {:ok, assertion}
end
