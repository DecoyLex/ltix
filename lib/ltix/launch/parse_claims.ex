defmodule Ltix.Launch.ParseClaims do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.Claims
  alias Ltix.Errors
  alias Ltix.PluginSet

  @impl Ltix.Step
  def call(%Ltix.Launch{raw: raw, plugins: plugins} = launch, _opts) do
    {parse_error, sent, endpoints} = Claims.parse_sent(raw, plugins)

    sent = Map.merge(launch.claims, sent)
    claims = Map.merge(PluginSet.data(plugins, Claims).defaults, sent)
    launch = %{launch | claims: claims, endpoints: Map.merge(launch.endpoints, endpoints)}

    check_error =
      case Claims.check(claims, sent, claims.message_type, plugins) do
        :ok -> nil
        {:error, error} -> error
      end

    # The step records the errors itself, to keep the claims that parsed.
    case Errors.collect([parse_error, check_error]) do
      :ok -> {:ok, launch}
      {:error, error} -> {:ok, %{launch | errors: launch.errors ++ [error]}}
    end
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.ClaimsParsed), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.ClaimsReceived), do: true
  def after?(_module), do: false
end
