defmodule Ltix.Launch.EveryMessageType do
  @moduledoc """
  Requirements for every message type.

  A module that calls `use Ltix.Launch.EveryMessageType` changes what every
  launch requires. It implements `Ltix.Launch.MessageType.Requirements`, and its
  `validator/1` receives the validator of each message type in the plugin set,
  and the validator for undeclared message types.

  ```elixir
  defmodule MyLibrary.Baseline do
    use Ltix.Launch.EveryMessageType

    @impl Ltix.Launch.MessageType.Requirements
    def validator(validator), do: required(validator, :context)
  end
  ```

  Core's `Ltix.Core.RequiredClaims` requires `version`, `deployment_id`, and
  `target_link_uri`.
  """
  use Ltix.Provider, hook: [Ltix.Launch.MessageType.Requirements]
end
