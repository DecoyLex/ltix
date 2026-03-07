defmodule Ltix.Errors.Security do
  @moduledoc """
  Error class for security framework violations.

  Covers JWT signature failures, token expiry, issuer/audience mismatches,
  algorithm restrictions, nonce replay, CSRF state mismatches, and key ID issues.
  """
  use Splode.ErrorClass, class: :security
end
