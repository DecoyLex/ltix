defmodule Ltix.Errors.Unknown.Unknown do
  @moduledoc "Generic unexpected error."
  use Splode.Error, fields: [:error], class: :unknown

  def message(%{error: error}) do
    if is_binary(error) do
      error
    else
      inspect(error)
    end
  end
end
