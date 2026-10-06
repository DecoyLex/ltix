defmodule Ltix.Test.Platform do
  @moduledoc """
  A simulated LTI platform for testing.

  Has everything needed to simulate platform-side behavior in tests, which
  is the registration and deployment (the records the tool stores), plus the
  platform's signing key. Sign tokens with
  `Ltix.Test.sign_id_token/3` and publish the key with `Ltix.JWK.to_jwks/1`.

  `tool_jwk` is the key the tool signs with in tests, and
  `Ltix.Test.verify_deep_linking_response/2` verifies against it.

  Created by `Ltix.Test.setup_platform!/1`.
  """

  alias Ltix.Deployable
  alias Ltix.Registerable

  @enforce_keys [:registration, :deployment, :jwk]
  defstruct [:registration, :deployment, :jwk, :tool_jwk]

  @type t :: %__MODULE__{
          registration: Registerable.t(),
          deployment: Deployable.t(),
          jwk: Ltix.JWK.t(),
          tool_jwk: Ltix.JWK.t() | nil
        }
end
