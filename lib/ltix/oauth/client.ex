defmodule Ltix.OAuth.Client do
  @moduledoc """
  Authenticated OAuth session for LTI Advantage service calls.

  Holds an access token, tracks which scopes were granted, and provides
  explicit refresh. Pass this struct to service functions like
  `Ltix.MembershipsService.get_members/2`.

  ## Refreshing

      client = Ltix.OAuth.Client.refresh!(client)

  ## Reusing tokens across contexts

  A token is valid across contexts (courses, launches) on the same
  registration. Reuse a cached token with different endpoints:

      {:ok, client_b} = Ltix.OAuth.Client.with_endpoints(client, %{
        Ltix.MembershipsService => course_b_endpoint
      })

  Or build from a previously cached `AccessToken`:

      {:ok, client} = Ltix.OAuth.Client.from_access_token(cached_token,
        registration: registration,
        endpoints: %{Ltix.MembershipsService => endpoint}
      )
  """

  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.ClientCredentials
  alias Ltix.Registerable
  alias Ltix.Registration

  defstruct [:access_token, :expires_at, :scopes, :registration, :req_options, endpoints: %{}]

  @type t :: %__MODULE__{
          access_token: String.t(),
          expires_at: DateTime.t(),
          scopes: MapSet.t(String.t()),
          registration: Registration.t(),
          req_options: keyword(),
          endpoints: %{module() => term()}
        }

  @expiry_buffer_seconds 60

  @doc """
  Check whether the client's token has expired.

  Uses a 60-second buffer to avoid using a token that is about to expire.

  ## Examples

      iex> client = %Ltix.OAuth.Client{
      ...>   access_token: "tok",
      ...>   expires_at: DateTime.add(DateTime.utc_now(), 3600),
      ...>   scopes: MapSet.new(),
      ...>   registration: nil,
      ...>   req_options: []
      ...> }
      iex> Ltix.OAuth.Client.expired?(client)
      false
  """
  # [Sec §7.1](https://www.imsglobal.org/spec/security/v1p0/#access-token-management)
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: expires_at}) do
    buffered = DateTime.add(expires_at, -@expiry_buffer_seconds)
    DateTime.compare(DateTime.utc_now(), buffered) != :lt
  end

  @doc """
  Check whether the client was granted a specific scope.

  ## Examples

      iex> client = %Ltix.OAuth.Client{
      ...>   access_token: "tok",
      ...>   expires_at: DateTime.utc_now(),
      ...>   scopes: MapSet.new(["scope:read"]),
      ...>   registration: nil,
      ...>   req_options: []
      ...> }
      iex> Ltix.OAuth.Client.has_scope?(client, "scope:read")
      true
      iex> Ltix.OAuth.Client.has_scope?(client, "scope:write")
      false
  """
  @spec has_scope?(t(), String.t()) :: boolean()
  def has_scope?(%__MODULE__{scopes: scopes}, scope) do
    MapSet.member?(scopes, scope)
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
      {:error,
       ScopeMismatch.exception(
         scope: scope,
         granted_scopes: MapSet.to_list(client.scopes),
         spec_ref: "Sec §4.1"
       )}
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
      {:error,
       ScopeMismatch.exception(
         scope: Enum.join(scopes, " or "),
         granted_scopes: MapSet.to_list(client.scopes),
         spec_ref: "Sec §4.1"
       )}
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

    with {:ok, token} <-
           ClientCredentials.request_token(client.registration, scopes,
             req_options: client.req_options
           ) do
      {:ok,
       %{
         client
         | access_token: token.access_token,
           expires_at: token.expires_at,
           scopes: MapSet.new(token.granted_scopes)
       }}
    else
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

  Validates endpoints and checks that the token's granted scopes cover
  the required scopes for all endpoints.

  ## Options

    * `:registration` (required) - any struct implementing `Ltix.Registerable`
    * `:endpoints` (required) - map of service modules to endpoint structs
    * `:req_options` - options passed through to `Req.request/2` (default: `[]`)
  """
  @spec from_access_token(AccessToken.t(), keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def from_access_token(%AccessToken{} = token, opts) do
    registerable = Keyword.fetch!(opts, :registration)
    endpoints = Keyword.fetch!(opts, :endpoints)
    req_options = Keyword.get(opts, :req_options, [])

    with {:ok, registration} <- Registerable.to_registration(registerable),
         :ok <- validate_endpoints(endpoints),
         :ok <- check_scope_coverage(collect_scopes(endpoints), token.granted_scopes) do
      {:ok,
       %__MODULE__{
         access_token: token.access_token,
         expires_at: token.expires_at,
         scopes: MapSet.new(token.granted_scopes),
         registration: registration,
         req_options: req_options,
         endpoints: endpoints
       }}
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

  Validates the new endpoints and checks that the client's granted scopes
  cover the required scopes. The token remains the same.
  """
  @spec with_endpoints(t(), %{module() => term()}) :: {:ok, t()} | {:error, Exception.t()}
  def with_endpoints(%__MODULE__{} = client, endpoints) do
    with :ok <- validate_endpoints(endpoints),
         :ok <- check_scope_coverage(collect_scopes(endpoints), MapSet.to_list(client.scopes)) do
      {:ok, %{client | endpoints: endpoints}}
    end
  end

  @doc """
  Same as `with_endpoints/2` but raises on error.
  """
  @spec with_endpoints!(t(), %{module() => term()}) :: t()
  def with_endpoints!(%__MODULE__{} = client, endpoints) do
    case with_endpoints(client, endpoints) do
      {:ok, client} -> client
      {:error, error} -> raise error
    end
  end

  # --- Private helpers ---

  defp validate_endpoints(endpoints) do
    Enum.reduce_while(endpoints, :ok, fn {module, endpoint}, :ok ->
      case module.validate_endpoint(endpoint) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp collect_scopes(endpoints) do
    endpoints
    |> Enum.flat_map(fn {module, endpoint} -> module.scopes(endpoint) end)
    |> Enum.uniq()
  end

  defp check_scope_coverage(required_scopes, granted_scopes) do
    granted_set = MapSet.new(granted_scopes)

    case Enum.find(required_scopes, fn scope -> not MapSet.member?(granted_set, scope) end) do
      nil ->
        :ok

      missing ->
        {:error,
         ScopeMismatch.exception(
           scope: missing,
           granted_scopes: granted_scopes,
           spec_ref: "Sec §4.1"
         )}
    end
  end
end
