defmodule TestPlugins.Records do
  @moduledoc false
  # A service plugin, and the service its endpoint claim belongs to.
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Records")
    |> Ltix.Plugin.add(TestPlugins.Records.Endpoint)
  end
end

defmodule TestPlugins.Records.Endpoint do
  @moduledoc false
  # The records endpoint claim, and the client assertion step that requests
  # its scope.
  use Ltix.Claim,
    claim: "https://tool.example.com/claim/records",
    name: :records_endpoint,
    strict: false,
    service: TestPlugins.Records,
    fields: [url: Zoi.string()]

  use Ltix.ClientAssertion

  alias Ltix.Errors.Invalid.InvalidField

  @scope "https://example.com/scope/records.readonly"

  @impl Ltix.Claim
  def new(attributes) do
    url = attributes[:url]

    case Ltix.HTTP.validate_url(url) do
      {:ok, _uri} ->
        {:ok, %__MODULE__{url: url}}

      {:error, _} ->
        {:error, InvalidField.invalid(__MODULE__, :url, url, "must be HTTPS")}
    end
  end

  @impl Ltix.Step
  def call(%{endpoints: %{TestPlugins.Records => _endpoint}} = assertion, _opts),
    do: {:ok, update_in(assertion.scopes, &(&1 ++ [@scope]))}

  def call(assertion, _opts), do: {:ok, assertion}
end

defmodule TestPlugins.Calendar do
  @moduledoc false
  # A second service plugin, with one scope.
  @behaviour Ltix.Plugin

  @impl Ltix.Plugin
  def plugin(_opts) do
    Ltix.Plugin.new(name: "Calendar")
    |> Ltix.Plugin.add(TestPlugins.Calendar.Endpoint)
  end
end

defmodule TestPlugins.Calendar.Endpoint do
  @moduledoc false
  use Ltix.Claim,
    claim: "https://tool.example.com/claim/calendar",
    name: :calendar_endpoint,
    strict: false,
    service: TestPlugins.Calendar,
    fields: [url: Zoi.string()]

  use Ltix.ClientAssertion

  @scope "https://example.com/scope/calendar.write"

  @impl Ltix.Claim
  def new(attributes), do: {:ok, struct!(__MODULE__, Map.new(attributes))}

  @impl Ltix.Step
  def call(%{endpoints: %{TestPlugins.Calendar => _endpoint}} = assertion, _opts),
    do: {:ok, update_in(assertion.scopes, &(&1 ++ [@scope]))}

  def call(assertion, _opts), do: {:ok, assertion}
end

defmodule TestPlugins.AssertionError do
  @moduledoc false
  # Returns the error in its `:error` option.
  use Ltix.ClientAssertion

  @impl Ltix.Step
  def call(_assertion, opts), do: {:error, Keyword.fetch!(opts, :error)}
end

defmodule TestPlugins.AssertionClaims do
  @moduledoc false
  # Adds the claims in its `:claims` option to the client assertion, and sends
  # `{:client_assertion, assertion}` to the calling process.
  use Ltix.ClientAssertion

  @impl Ltix.Step
  def init(opts), do: Keyword.fetch!(opts, :claims)

  @impl Ltix.Step
  def call(assertion, claims) do
    send(self(), {:client_assertion, assertion})
    {:ok, update_in(assertion.claims, &Map.merge(&1, claims))}
  end
end

defmodule TestPlugins.AssertionPlugins do
  @moduledoc false
  # Sends `{:assertion_plugins, plugins}` to the calling process with the
  # client assertion's plugin set.
  use Ltix.ClientAssertion

  @impl Ltix.Step
  def call(assertion, _opts) do
    send(self(), {:assertion_plugins, assertion.plugins})
    {:ok, assertion}
  end
end

defmodule TestPlugins.UncheckedEndpoint do
  @moduledoc false
  # Declares an endpoint claim without `new/1`.
  use Ltix.Claim,
    claim: "https://tool.example.com/claim/unchecked",
    name: :unchecked_endpoint,
    service: TestPlugins.Unchecked,
    fields: [url: Zoi.string()]
end
