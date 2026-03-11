defmodule Ltix.LaunchContext do
  @moduledoc """
  The validated output of a successful LTI launch.

  Wraps the parsed `%LaunchClaims{}` together with the resolved
  `%Registration{}` and `%Deployment{}` that were used during validation.

  Access claim data through `context.claims` — for example,
  `context.claims.roles`, `context.claims.resource_link.id`, or
  `context.claims.target_link_uri`.

  ## Fields

  - `:claims` — all parsed claim data from the ID Token
  - `:registration` — the platform registration matched during login
  - `:deployment` — the deployment matched from the JWT's `deployment_id`
  """

  alias Ltix.Deployment
  alias Ltix.LaunchClaims
  alias Ltix.Registration

  defstruct [:claims, :registration, :deployment]

  @type t :: %__MODULE__{
          claims: LaunchClaims.t(),
          registration: Registration.t(),
          deployment: Deployment.t()
        }
end
