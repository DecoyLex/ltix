defmodule RaisingRegistration do
  @moduledoc false

  defstruct []

  defimpl Ltix.Registerable do
    def to_registration(_record), do: raise(ArgumentError, "registration conversion failed")
  end
end
