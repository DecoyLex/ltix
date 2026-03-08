defmodule Ltix.LaunchClaims.Role.Parser do
  @moduledoc """
  Defines a behaviour for parsing role URIs into `%Role{}` structs.
  """

  alias Ltix.LaunchClaims.Role

  @callback parse(uri :: String.t()) :: {:ok, Role.t()} | :error
  @callback to_uri(role :: Role.t_without_uri()) :: {:ok, String.t()} | :error
  @optional_callbacks [to_uri: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Ltix.LaunchClaims.Role.Parser
    end
  end
end
