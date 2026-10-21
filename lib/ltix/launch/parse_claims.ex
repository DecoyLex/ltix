defmodule Ltix.Launch.ParseClaims do
  @moduledoc false
  use Ltix.Launch

  @impl Ltix.Step
  def call(%Ltix.Launch{raw: raw, plugins: plugins} = launch, _opts) do
    {parse_error, sent, endpoints} = Ltix.Claims.parse_sent(raw, plugins)

    claims = Map.merge(Ltix.Claims.defaults(plugins), Map.merge(launch.claims, sent))
    launch = %{launch | claims: claims, endpoints: Map.merge(launch.endpoints, endpoints)}

    case parse_error do
      nil -> {:ok, launch}
      # The step records the error itself, to keep the claims that parsed.
      error -> {:ok, %{launch | errors: launch.errors ++ [error]}}
    end
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.ClaimsParsed), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.ClaimsReceived), do: true
  def after?(_module), do: false
end
