defmodule Ltix.Errors.Invalid do
  @moduledoc """
  Error class for spec-violating input data.

  Covers malformed JWTs, missing/invalid claims, missing OIDC parameters,
  invalid options and fields, and unknown registrations/deployments.
  """
  use Ltix.Errors, type: :error_class, class: :invalid
end
