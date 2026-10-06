defmodule Ltix.OAuth.Client do
  @moduledoc """
  Authenticated OAuth session for LTI Advantage service calls.

  Holds an `Ltix.OAuth.AccessToken` with the scopes it was granted, the
  registration it was requested for, and the service endpoints it calls, and
  provides explicit refresh. Pass this struct to service functions like
  `Ltix.MembershipsService.list_members/2`.

  `registration` is the struct you authenticated with, which can be your own
  struct implementing `Ltix.Registerable`.

  ## Refreshing

      client = Ltix.OAuth.Client.refresh!(client)

  ## Reusing tokens across contexts

  A token is valid across contexts (courses, launches) on the same
  registration. Reuse a cached token with different endpoints:

      {:ok, client_b} = Ltix.OAuth.Client.with_endpoints(client, %{
        Ltix.MembershipsService => course_b_endpoint
      })

  Or cache `client.token` and build a client from it later:

      {:ok, client} = Ltix.OAuth.Client.from_access_token(cached_token,
        registration: registration,
        endpoints: %{Ltix.MembershipsService => endpoint}
      )
  """

  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.Errors.Security.AccessTokenExpired
  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.ClientCredentials
  alias Ltix.Options
  alias Ltix.Records
  alias Ltix.Registerable

  defstruct [
    :token,
    :registration,
    :storage_adapter,
    :req_options,
    :local_network_access,
    endpoints: %{}
  ]

  @type t :: %__MODULE__{
          token: AccessToken.t(),
          registration: Registerable.t(),
          storage_adapter: module() | nil,
          req_options: keyword(),
          local_network_access: :none | :local | :loopback | nil,
          endpoints: %{module() => term()}
        }

  @option_fields [
    req_options:
      Zoi.keyword(Zoi.any(), description: "Options passed through to `Req.request/2`.")
      |> Zoi.default([]),
    local_network_access: Ltix.HTTP.local_network_access_option(),
    storage_adapter:
      Zoi.module(
        description:
          "Module implementing `Ltix.StorageAdapter`, which signs token requests. Defaults to the application configuration."
      ),
    require_all_scopes:
      Zoi.boolean(
        description:
          "Return a `ScopeMismatch` error unless every scope the endpoints need was granted."
      )
      |> Zoi.default(false)
  ]

  @with_endpoints_schema Zoi.keyword(Keyword.take(@option_fields, [:require_all_scopes]),
                           unrecognized_keys: :error
                         )

  @from_access_token_schema Zoi.keyword(
                              [
                                registration:
                                  Zoi.any(
                                    description: "Any struct implementing `Ltix.Registerable`."
                                  )
                                  |> Zoi.required(),
                                endpoints:
                                  Zoi.map(Zoi.atom(), Zoi.any(),
                                    description: "Map of service modules to endpoint structs."
                                  )
                                  |> Zoi.required()
                              ] ++ @option_fields,
                              unrecognized_keys: :error
                            )

  # Options shared by every entry point that builds a client.
  @doc false
  def option_fields, do: @option_fields

  @doc """
  Check whether the client's token has expired, the same way as
  `Ltix.OAuth.AccessToken.expired?/1`.

  ## Examples

      iex> token = %Ltix.OAuth.AccessToken{expires_at: DateTime.add(DateTime.utc_now(), 3600)}
      iex> Ltix.OAuth.Client.expired?(%Ltix.OAuth.Client{token: token})
      false
  """
  # [Sec §7.1](https://www.imsglobal.org/spec/security/v1p0/#access-token-management)
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{token: token}), do: AccessToken.expired?(token)

  @doc """
  Check whether the client's token was granted a specific scope.

  ## Examples

      iex> token = %Ltix.OAuth.AccessToken{granted_scopes: MapSet.new(["scope:read"])}
      iex> client = %Ltix.OAuth.Client{token: token}
      iex> Ltix.OAuth.Client.has_scope?(client, "scope:read")
      true
      iex> Ltix.OAuth.Client.has_scope?(client, "scope:write")
      false
  """
  @spec has_scope?(t(), String.t()) :: boolean()
  def has_scope?(%__MODULE__{token: token}, scope) do
    MapSet.member?(token.granted_scopes, scope)
  end

  @doc """
  Require a token that hasn't expired, returning
  `Ltix.Errors.Security.AccessTokenExpired` if it has.

  ## Examples

      iex> token = %Ltix.OAuth.AccessToken{expires_at: DateTime.add(DateTime.utc_now(), 3600)}
      iex> Ltix.OAuth.Client.require_unexpired(%Ltix.OAuth.Client{token: token})
      :ok
  """
  # [Sec §7.1](https://www.imsglobal.org/spec/security/v1p0/#access-token-management)
  @spec require_unexpired(t()) :: :ok | {:error, Exception.t()}
  def require_unexpired(%__MODULE__{token: token} = client) do
    if expired?(client) do
      {:error, AccessTokenExpired.exception(expires_at: token.expires_at, spec_ref: "Sec §7.1")}
    else
      :ok
    end
  end

  @doc """
  Require a specific scope, returning an error if not granted.
  """
  # [Sec §4.1](https://www.imsglobal.org/spec/security/v1p0/#using-oauth-2-0-client-credentials-grant)
  @spec require_scope(t(), String.t()) :: :ok | {:error, Exception.t()}
  def require_scope(%__MODULE__{} = client, scope) do
    if has_scope?(client, scope) do
      :ok
    else
      {:error, scope_mismatch(client, [scope])}
    end
  end

  @doc """
  Require any one of the given scopes.

  Returns `:ok` if at least one scope from the list was granted.
  """
  @spec require_any_scope(t(), [String.t()]) :: :ok | {:error, Exception.t()}
  def require_any_scope(%__MODULE__{} = client, scopes) do
    if Enum.any?(scopes, &has_scope?(client, &1)) do
      :ok
    else
      {:error, scope_mismatch(client, scopes)}
    end
  end

  # --- Refresh ---

  @doc """
  If expired, re-acquire the token using the stored registration and endpoints.
  Otherwise, return the client unchanged.

  Re-derives requested scopes from endpoints via each service's `scopes/1`
  callback, so a transient partial grant does not become permanent.
  """
  # [Sec §7.1](https://www.imsglobal.org/spec/security/v1p0/#access-token-management)
  @spec refresh(t()) :: {:ok, t()} | {:error, Exception.t()}
  def refresh(%__MODULE__{} = client) do
    if expired?(client) do
      force_refresh(client)
    else
      {:ok, client}
    end
  end

  @doc """
  Same as `refresh/1` but raises on error.
  """
  @spec refresh!(t()) :: t()
  def refresh!(%__MODULE__{} = client) do
    case refresh(client) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  @doc """
  Force a refresh regardless of expiry.
  Useful for testing or if the client wants to proactively refresh before making a batch of calls.
  """
  @spec force_refresh(t()) :: {:ok, t()} | {:error, Exception.t()}
  def force_refresh(%__MODULE__{} = client) do
    scopes = collect_scopes(client.endpoints)

    case ClientCredentials.request_token_span(
           :refresh,
           client.registration,
           scopes,
           storage_adapter: client.storage_adapter,
           req_options: client.req_options,
           local_network_access: client.local_network_access
         ) do
      {:ok, token} ->
        {:ok, %{client | token: token}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Same as `force_refresh/1` but raises on error.
  """
  @spec force_refresh!(t()) :: t()
  def force_refresh!(%__MODULE__{} = client) do
    case force_refresh(client) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  @doc """
  Build a client from a cached `AccessToken`.

  The token may lack some of the scopes the endpoints need.

  ## Options

  #{Zoi.describe(@from_access_token_schema)}
  """
  @spec from_access_token(AccessToken.t(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def from_access_token(%AccessToken{} = token, opts) do
    opts = Options.parse!(opts, @from_access_token_schema)
    registerable = Keyword.fetch!(opts, :registration)
    endpoints = Keyword.fetch!(opts, :endpoints)
    req_options = Keyword.fetch!(opts, :req_options)

    with {:ok, _registration} <- Records.convert!(registerable, :registration, :registration),
         :ok <- validate_endpoints(endpoints) do
      check_granted_scopes(
        %__MODULE__{
          token: token,
          registration: registerable,
          storage_adapter: Keyword.get(opts, :storage_adapter),
          req_options: req_options,
          local_network_access: Keyword.get(opts, :local_network_access),
          endpoints: endpoints
        },
        Keyword.fetch!(opts, :require_all_scopes)
      )
    end
  end

  @doc """
  Same as `from_access_token/2` but raises on error.
  """
  @spec from_access_token!(AccessToken.t(), keyword()) :: t()
  def from_access_token!(%AccessToken{} = token, opts) do
    case from_access_token(token, opts) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  @doc """
  Swap endpoints on an existing client.

  The token remains the same, so it may lack some of the scopes the new endpoints need.

  ## Options

  #{Zoi.describe(@with_endpoints_schema)}
  """
  @spec with_endpoints(t(), %{module() => term()}, keyword()) ::
          {:ok, t()} | {:error, Exception.t()}
  def with_endpoints(%__MODULE__{} = client, endpoints, opts \\ []) do
    opts = Options.parse!(opts, @with_endpoints_schema)

    case validate_endpoints(endpoints) do
      :ok ->
        check_granted_scopes(
          %{client | endpoints: endpoints},
          Keyword.fetch!(opts, :require_all_scopes)
        )

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Same as `with_endpoints/3` but raises on error.
  """
  @spec with_endpoints!(t(), %{module() => term()}, keyword()) :: t()
  def with_endpoints!(%__MODULE__{} = client, endpoints, opts \\ []) do
    case with_endpoints(client, endpoints, opts) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec validate_endpoints(%{module() => term()}) :: :ok | {:error, Exception.t()}
  def validate_endpoints(endpoints) do
    Enum.reduce_while(endpoints, :ok, fn {module, endpoint}, :ok ->
      case module.validate_endpoint(endpoint) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc false
  @spec collect_scopes(%{module() => term()}) :: [String.t()]
  def collect_scopes(endpoints) do
    endpoints
    |> Enum.flat_map(fn {module, endpoint} -> module.scopes(endpoint) end)
    |> Enum.uniq()
  end

  # With `require_all_scopes`, every scope the endpoints need must be granted.
  # [Sec §4.1](https://www.imsglobal.org/spec/security/v1p0/#using-oauth-2-0-client-credentials-grant)
  defp check_granted_scopes(%__MODULE__{} = client, false), do: {:ok, client}

  defp check_granted_scopes(%__MODULE__{} = client, true) do
    case Enum.reject(collect_scopes(client.endpoints), &has_scope?(client, &1)) do
      [] -> {:ok, client}
      missing -> {:error, Ltix.Errors.combine(Enum.map(missing, &scope_mismatch(client, [&1])))}
    end
  end

  defp scope_mismatch(client, scopes) do
    ScopeMismatch.exception(
      scopes: scopes,
      granted_scopes: MapSet.to_list(client.token.granted_scopes),
      spec_ref: "Sec §4.1"
    )
  end
end
