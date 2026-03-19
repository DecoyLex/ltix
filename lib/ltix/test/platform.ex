defmodule Ltix.Test.Platform do
  @moduledoc """
  A simulated LTI platform for testing.

  Holds everything needed to simulate platform-side behavior in tests:
  the registration and deployment (what the tool knows), plus the platform's
  key material (what only the platform knows) for signing JWTs.

  Created by `Ltix.Test.setup_platform!/1`.
  """

  alias Ltix.Deployable
  alias Ltix.Registerable

  defstruct [:registration, :deployment, :private_key, :public_key, :kid, :jwks]

  @type t :: %__MODULE__{
          registration: Registerable.t(),
          deployment: Deployable.t(),
          private_key: JOSE.JWK.t(),
          public_key: JOSE.JWK.t(),
          kid: String.t(),
          jwks: map()
        }
end
