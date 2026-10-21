defmodule Ltix.Claims.RoleScopeMentor do
  @moduledoc """
  The subject identifiers of the users a mentor is responsible for, such as a
  parent's children, from the role-scope mentor claim.
  """

  # [Core §5.4.3](https://www.imsglobal.org/spec/lti/v1p3/#role-scope-mentor-claim)
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor",
    name: :role_scope_mentor,
    schema: Zoi.list(Zoi.string()),
    strict: false
end
