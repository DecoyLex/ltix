defmodule TestPlugins.TestRequest do
  @moduledoc false
  # Declares the message type `LtiTestRequest`.
  use Ltix.Launch.MessageType

  @impl Ltix.Launch.MessageType
  def validator, do: new("LtiTestRequest")
end

defmodule TestPlugins.OtherTestRequest do
  @moduledoc false
  # Declares `LtiTestRequest` too.
  use Ltix.Launch.MessageType

  @impl Ltix.Launch.MessageType
  def validator, do: new("LtiTestRequest")
end

defmodule TestPlugins.RequireContext do
  @moduledoc false
  # Requires `context` in resource link launches and test launches, and
  # makes it optional in Deep Linking requests.
  use Ltix.ResourceLinkRequest
  use Ltix.DeepLinkingRequest
  use TestPlugins.TestRequest

  @impl Ltix.Launch.MessageType.Requirements
  def validator(%{message_type: "LtiDeepLinkingRequest"} = validator),
    do: optional(validator, :context)

  def validator(validator), do: required(validator, :context)
end

defmodule TestPlugins.RequireLisForFiles do
  @moduledoc false
  # Requires `lis` in Deep Linking requests that accept files.
  use Ltix.DeepLinkingRequest

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator),
    do: required(validator, :lis, when: includes(:deep_linking_settings, :accept_types, "file"))
end

defmodule TestPlugins.Graded do
  @moduledoc false
  # Holds when the launch has an AGS endpoint.
  @behaviour Ltix.Validator.Condition

  @impl Ltix.Validator.Condition
  def met?(_args, claims, _opts), do: claims.ags_endpoint != nil

  @impl Ltix.Validator.Condition
  def describe(_args), do: "the launch has an AGS endpoint"
end

defmodule TestPlugins.RequireContextWhenGraded do
  @moduledoc false
  # Requires `context` in graded resource link launches.
  use Ltix.ResourceLinkRequest

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator), do: required(validator, :context, when: TestPlugins.Graded)
end

defmodule TestPlugins.Baseline do
  @moduledoc false
  # Requires `context` and `roles` in every message type.
  use Ltix.Launch.EveryMessageType

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator), do: defaults(validator, required: [:context, :roles])
end

defmodule TestPlugins.OptionalRoles do
  @moduledoc false
  # Makes `roles` optional in resource link launches.
  use Ltix.ResourceLinkRequest

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator), do: override(validator, :roles, :optional)
end

defmodule TestPlugins.OtherOptionalRoles do
  @moduledoc false
  use Ltix.ResourceLinkRequest

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator), do: override(validator, :roles, :optional)
end

defmodule TestPlugins.RequireRoles do
  @moduledoc false
  use Ltix.ResourceLinkRequest

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator), do: required(validator, :roles)
end

defmodule TestPlugins.RequireUndeclared do
  @moduledoc false
  # States a claim no plugin declares.
  use Ltix.Launch.EveryMessageType

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator), do: required(validator, :proctoring_session)
end

defmodule TestPlugins.OptionalDeploymentId do
  @moduledoc false
  # States that every message type may leave out `deployment_id`, which Core
  # requires.
  use Ltix.Launch.EveryMessageType

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator), do: optional(validator, :deployment_id)
end

defmodule TestPlugins.WithoutDeploymentId do
  @moduledoc false
  # Overrides `deployment_id` to optional in every message type.
  use Ltix.Launch.EveryMessageType

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator), do: override(validator, :deployment_id, :optional)
end

defmodule TestPlugins.WithoutMessageType do
  @moduledoc false
  # Overrides `message_type` to optional in every message type.
  use Ltix.Launch.EveryMessageType

  @impl Ltix.Launch.MessageType.Requirements
  def validator(validator), do: override(validator, :message_type, :optional)
end
