defmodule Ltix.Errors.Unknown do
  @moduledoc """
  Catch-all error class for unexpected errors.
  """
  use Splode.ErrorClass, class: :unknown
end
