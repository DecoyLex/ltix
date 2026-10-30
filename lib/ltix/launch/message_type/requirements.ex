defmodule Ltix.Launch.MessageType.Requirements do
  @moduledoc """
  The behaviour of modules that change what a message type requires.

  A module changes one message type with `use` and the message type's module,
  such as `use Ltix.DeepLinkingRequest`, or every message type with
  `use Ltix.Launch.EveryMessageType`. It implements `c:validator/1`, which
  receives the message type's validator and returns it with more requirements.
  The builders of `Ltix.Validator`, such as `Ltix.Validator.required/3`, are
  imported.

  ```elixir
  defmodule MyLibrary.RequireContext do
    use Ltix.ResourceLinkRequest

    @impl Ltix.Launch.MessageType.Requirements
    def validator(validator), do: required(validator, :context)
  end
  ```

  A plugin adds the module with `Ltix.Plugin.add/2`. A module that changes a
  message type that isn't in the plugin set does nothing.

  A module that changes several message types matches on each one.

  ```elixir
  defmodule MyLibrary.Context do
    use Ltix.ResourceLinkRequest
    use Ltix.DeepLinkingRequest

    @impl Ltix.Launch.MessageType.Requirements
    def validator(%{message_type: "LtiResourceLinkRequest"} = validator),
      do: required(validator, :context)

    def validator(%{message_type: "LtiDeepLinkingRequest"} = validator),
      do: optional(validator, :context)
  end
  ```
  """

  @doc """
  Returns the validator with the module's requirements added.
  """
  @callback validator(Ltix.Validator.t()) :: Ltix.Validator.t()

  defmacro __using__(_opts) do
    quote do
      require Ltix.Behaviour

      Ltix.Behaviour.declare_once(Ltix.Launch.MessageType.Requirements, do: nil)

      use Ltix.Validator
    end
  end
end
