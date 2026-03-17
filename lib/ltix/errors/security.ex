defmodule Ltix.Errors.Security do
  @moduledoc """
  Error class for security framework violations.

  Covers JWT signature failures, token expiry, issuer/audience mismatches,
  algorithm restrictions, nonce replay, CSRF state mismatches, and key ID issues.
  """
  use Ltix.Errors, type: :error_class, class: :security
end
