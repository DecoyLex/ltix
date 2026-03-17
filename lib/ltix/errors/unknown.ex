defmodule Ltix.Errors.Unknown do
  @moduledoc """
  Catch-all error class for unexpected errors.
  """
  use Ltix.Errors, type: :error_class, class: :unknown
end
