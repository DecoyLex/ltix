defmodule Ltix.LaunchContext do
  @moduledoc """
  Validated output of a successful LTI launch.

  Access claim data through `context.claims` — for example,
  `context.claims.roles`, `context.claims.resource_link.id`, or
  `context.claims.target_link_uri`.

  ## Fields

    * `:claims` — parsed claim data from the ID Token
    * `:registration` — whatever your `c:Ltix.StorageAdapter.get_registration/2`
      returned. Access your own fields (database IDs, tenant info, etc.)
      directly on this struct.
    * `:deployment` — whatever your `c:Ltix.StorageAdapter.get_deployment/2`
      returned.
  """

  alias Ltix.{Deployable, LaunchClaims, Registerable}

  defstruct [:claims, :registration, :deployment]

  @type t :: %__MODULE__{
          claims: LaunchClaims.t(),
          registration: Registerable.t(),
          deployment: Deployable.t()
        }
end
