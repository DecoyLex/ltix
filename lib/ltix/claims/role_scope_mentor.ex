defmodule Ltix.Claims.RoleScopeMentor do
  @moduledoc """
  The subject identifiers of the users a mentor is responsible for, such as a
  parent's children, from the role-scope mentor claim.

  Read it from `launch.claims.role_scope_mentor`. When the value is malformed,
  it's `nil` and the launch continues. Ltix rejects a launch that lists users
  here without the Mentor role (see `Ltix.Role.mentor?/1`).
  """

  # [Core §5.4.3](https://www.imsglobal.org/spec/lti/v1p3/#role-scope-mentor-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor",
    name: :role_scope_mentor,
    schema: Zoi.list(Zoi.string()),
    strict: false

  # [Core §5.4.3](https://www.imsglobal.org/spec/lti/v1p3/#role-scope-mentor-claim)
  @impl Ltix.Claim
  def check([], _claims), do: :ok

  def check(_subjects, claims) do
    if Ltix.Role.mentor?(Map.get(claims, :roles, [])),
      do: :ok,
      else: {:error, "requires the Mentor role in roles"}
  end
end
