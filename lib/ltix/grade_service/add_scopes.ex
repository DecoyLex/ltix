defmodule Ltix.GradeService.AddScopes do
  @moduledoc false
  use Ltix.ClientAssertion

  alias Ltix.GradeService.Endpoint

  @impl Ltix.Step
  # [AGS §3.1](https://www.imsglobal.org/spec/lti-ags/v2p0/#assignment-and-grade-service-claim)
  def call(%{endpoints: %{Ltix.GradeService => %Endpoint{scopes: scopes}}} = assertion, _opts),
    do: {:ok, update_in(assertion.scopes, &(&1 ++ List.wrap(scopes)))}

  def call(assertion, _opts), do: {:ok, assertion}
end
