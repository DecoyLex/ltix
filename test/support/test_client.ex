defmodule TestClient do
  @moduledoc false

  # Builds an OAuth client for `registration` and `endpoints` with an access
  # token, without a token request. Its options are the token's granted
  # `:scopes` (defaults to none), its `:access_token` (defaults to
  # `"test-token"`), when it `:expires_at` (defaults to an hour from now),
  # the client's `:req_options` (defaults to none), its `:local_network_access`
  # (defaults to the application config), and the `:plugins` list the
  # client keeps (defaults to no plugins).

  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.Client

  def build(registration, endpoints, opts \\ []) do
    token = %AccessToken{
      access_token: Keyword.get(opts, :access_token, "test-token"),
      token_type: "bearer",
      expires_at:
        Keyword.get_lazy(opts, :expires_at, fn -> DateTime.add(DateTime.utc_now(), 3600) end),
      granted_scopes: MapSet.new(Keyword.get(opts, :scopes, []))
    }

    Client.from_access_token!(token,
      registration: registration,
      endpoints: endpoints,
      req_options: Keyword.get(opts, :req_options, []),
      local_network_access: Keyword.get(opts, :local_network_access),
      plugins: Keyword.get(opts, :plugins, [])
    )
  end
end
