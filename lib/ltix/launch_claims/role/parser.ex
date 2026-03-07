defmodule Ltix.LaunchClaims.Role.Parser do
  @moduledoc """
  Defines a behaviour for parsing role URIs into `%Role{}` structs.
  """

  alias Ltix.LaunchClaims.Role

  @callback parse(uri :: String.t()) :: {:ok, Role.t()} | :error

  defmacro __using__(_opts) do
    quote do
      @behaviour Ltix.LaunchClaims.Role.Parser
    end
  end
end
