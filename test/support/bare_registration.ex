defmodule BareRegistration do
  @moduledoc false

  defstruct [:registration]

  defimpl Ltix.Registerable do
    def to_registration(%{registration: registration}), do: registration
  end
end
