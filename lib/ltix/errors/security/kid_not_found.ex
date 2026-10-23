defmodule Ltix.Errors.Security.KidNotFound do
  @moduledoc "kid not found in the platform's key set."
  use Ltix.Errors, fields: [:kid], class: :security

  def message(%{kid: kid}) do
    "Key not found in the platform's key set for kid: #{kid}"
  end
end
