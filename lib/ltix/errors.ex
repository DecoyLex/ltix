defmodule Ltix.Errors do
  @moduledoc """
  Structured error types for LTI 1.3 validation.

  Uses Splode for composable, class-based errors. Three error classes:

  - `:invalid` — Spec-violating input (bad claims, missing params)
  - `:security` — Security framework violations (signature, nonce, expiry)
  - `:unknown` — Unexpected / catch-all errors
  """
  use Splode,
    error_classes: [
      invalid: Ltix.Errors.Invalid,
      security: Ltix.Errors.Security,
      unknown: Ltix.Errors.Unknown
    ],
    unknown_error: Ltix.Errors.Unknown.Unknown
end
