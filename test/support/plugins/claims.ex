defmodule TestPlugins.Traced do
  @moduledoc false
  # Declares a claim and sends `{:parsed, value}` to the calling process when
  # Ltix parses it.
  use Ltix.Claim, claim: "https://tool.example.com/claim/traced", name: :traced

  @impl Ltix.Property
  def parse(value, _opts) do
    send(self(), {:parsed, value})
    {:ok, value}
  end
end

defmodule TestPlugins.OtherContext do
  @moduledoc false
  # Declares the claim `Ltix.Claims.Context` declares.
  use Ltix.Claim,
    claim: "https://purl.imsglobal.org/spec/lti/claim/context",
    name: :other_context
end

defmodule TestPlugins.Course do
  @moduledoc false
  # Declares the short name `Ltix.Claims.Context` declares.
  use Ltix.Claim, claim: "https://tool.example.com/claim/course", name: :context
end

defmodule TestPlugins.Grades do
  @moduledoc false
  # Declares the endpoint `Ltix.GradeService.Endpoint` declares.
  use Ltix.Claim,
    claim: "https://tool.example.com/claim/grades",
    name: :grades,
    service: Ltix.GradeService
end

defmodule TestPlugins.Failing do
  @moduledoc false
  # Declares a claim whose `parse/2` returns the error in its `:reason` option,
  # or raises the exception in its `:raise` option.
  use Ltix.Claim,
    claim: "https://tool.example.com/claim/failing",
    name: :failing

  @impl Ltix.Property
  def parse(_value, opts) do
    case Keyword.fetch(opts, :raise) do
      {:ok, exception} -> raise(exception)
      :error -> {:error, Keyword.fetch!(opts, :reason)}
    end
  end
end

defmodule TestPlugins.ReadClaims do
  @moduledoc false
  # A launch step that sends `{:claims, claims}` after `Ltix.Launch.ClaimsParsed`.
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, _opts) do
    send(self(), {:claims, launch.claims})
    {:ok, launch}
  end

  @impl Ltix.Ordered
  def after?(Ltix.Launch.ClaimsParsed), do: true
  def after?(_module), do: false
end

defmodule TestPlugins.AddTenant do
  @moduledoc false
  # A launch step that writes a claim between `Ltix.Launch.Verified` and
  # `Ltix.Launch.ClaimsReceived`.
  use Ltix.Launch

  @impl Ltix.Step
  def call(launch, _opts), do: {:ok, put_in(launch.claims[:tenant], "acme")}

  @impl Ltix.Ordered
  def after?(Ltix.Launch.Verified), do: true
  def after?(_module), do: false

  @impl Ltix.Ordered
  def before?(Ltix.Launch.ClaimsReceived), do: true
  def before?(_module), do: false
end

defmodule TestPlugins.Note do
  @moduledoc false
  # A vendor's note on object claims that no other test plugin extends.
  use Ltix.Claims.ToolPlatform, name: :note, property: "https://vendor.example.com/note"
  use Ltix.Claims.LIS
  use Ltix.Claims.Organization
  use Ltix.Claims.ActualUser
  use Ltix.DeepLinking.Settings
  use Ltix.GradeService.Endpoint
  use Ltix.MembershipsService.Endpoint
end
