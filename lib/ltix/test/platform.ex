defmodule Ltix.Test.Platform do
  @moduledoc """
  A simulated LTI platform for testing.

  Holds everything needed to simulate platform-side behavior in tests:
  the registration and deployment (what the tool knows), plus the platform's
  signing key. Sign tokens with
  `Ltix.Test.sign_id_token/3` and publish the key with `Ltix.JWK.to_jwks/1`.

  Created by `Ltix.Test.setup_platform!/1`.
  """

  alias Ltix.Deployable
  alias Ltix.Registerable

  @enforce_keys [:registration, :deployment, :jwk]
  defstruct [:registration, :deployment, :jwk]

  @type t :: %__MODULE__{
          registration: Registerable.t(),
          deployment: Deployable.t(),
          jwk: Ltix.JWK.t()
        }
end
