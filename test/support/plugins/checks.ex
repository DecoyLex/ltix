defmodule TestPlugins.TitledContext do
  @moduledoc false
  # Requires a title on the context of Deep Linking requests.
  use Ltix.Claims.Check,
    claim: "https://purl.imsglobal.org/spec/lti/claim/context",
    message_types: ["LtiDeepLinkingRequest"]

  @impl Ltix.Claims.Check
  def check(%{title: nil}, _claims), do: {:error, "must have a title"}
  def check(_context, _claims), do: :ok
end

defmodule TestPlugins.LabeledContext do
  @moduledoc false
  # Requires a label on the context of every launch.
  use Ltix.Claims.Check, claim: "https://purl.imsglobal.org/spec/lti/claim/context"

  @impl Ltix.Claims.Check
  def check(%{label: nil}, _claims), do: {:error, "must have a label"}
  def check(_context, _claims), do: :ok
end

defmodule TestPlugins.MentorWithoutRole do
  @moduledoc false
  # Accepts role-scope mentors without the Mentor role in test launches.
  use Ltix.Claims.Override, check: Ltix.Claims.RoleScopeMentor, message_types: ["LtiTestRequest"]

  @impl Ltix.Claims.Override
  def check(_subjects, _claims), do: :ok
end

defmodule TestPlugins.OtherMentorWithoutRole do
  @moduledoc false
  use Ltix.Claims.Override,
    check: Ltix.Claims.RoleScopeMentor,
    message_types: ["LtiResourceLinkRequest", "LtiTestRequest"]

  @impl Ltix.Claims.Override
  def check(_subjects, _claims), do: :ok
end

defmodule TestPlugins.NextVersion do
  @moduledoc false
  # Accepts version 1.4.0 in test launches.
  use Ltix.Claims.Override, check: Ltix.Claims.Version, message_types: ["LtiTestRequest"]

  @impl Ltix.Claims.Override
  def check("1.4.0", _claims), do: :ok
  def check(_version, _claims), do: {:error, "must be 1.4.0"}
end

defmodule TestPlugins.UndeclaredCheck do
  @moduledoc false
  # Checks a claim no plugin declares.
  use Ltix.Claims.Check, claim: "https://tool.example.com/claim/undeclared"

  @impl Ltix.Claims.Check
  def check(_value, _claims), do: :ok
end

defmodule TestPlugins.Placement do
  @moduledoc false
  # Declares a `placement` property of the launch presentation claim.
  use Ltix.Claims.LaunchPresentation,
    property: "placement",
    name: :placement

  @impl Ltix.Property
  def parse(placements, _opts), do: Zoi.parse(Zoi.list(Zoi.string()), placements)
end

defmodule TestPlugins.OtherPlacement do
  @moduledoc false
  use Ltix.Claims.LaunchPresentation,
    property: "placement",
    name: :other_placement
end

defmodule TestPlugins.LinkColor do
  @moduledoc false
  # Declares a `color` property of the resource link claim.
  use Ltix.Claims.ResourceLink,
    property: "color",
    name: :color

  @impl Ltix.Property
  def parse(color, _opts) when is_binary(color), do: {:ok, color}
  def parse(_color, _opts), do: {:error, "must be a string"}
end

defmodule TestPlugins.Session do
  @moduledoc false
  # Declares a vendor's session claim.
  use Ltix.Claim,
    claim: "https://vendor.example.com/session",
    name: :session,
    fields: [
      id: Zoi.string(),
      started_at: Zoi.integer() |> Zoi.optional()
    ]
end

defmodule TestPlugins.WriteClaims do
  @moduledoc false
  # A launch step between `Ltix.Launch.Verified` and
  # `Ltix.Launch.ClaimsReceived`. It writes the `tenant` claim and adds a session
  # to the raw claims.
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, _opts) do
    launch = put_in(launch.claims[:tenant], "acme")
    {:ok, put_in(launch.raw["https://vendor.example.com/session"], %{"id" => "from-step"})}
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.ClaimsReceived), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.Verified), do: true
  def after?(_module), do: false
end

defmodule TestPlugins.SessionRoom do
  @moduledoc false
  # A property of the vendor's session claim.
  use TestPlugins.Session,
    property: "room",
    name: :room
end
