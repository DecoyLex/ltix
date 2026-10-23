defmodule Ltix.OAuth.ClientTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid
  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.Client

  doctest Client

  @test_scope "https://example.com/scope/test.readonly"
  @other_scope "https://example.com/scope/other.write"

  defmodule TestService do
    @behaviour Ltix.AdvantageService

    @impl Ltix.AdvantageService
    def endpoint_from_claims(_), do: :error

    @impl Ltix.AdvantageService
    def validate_endpoint(endpoint) when endpoint in [:valid_endpoint, :other_valid_endpoint],
      do: :ok

    def validate_endpoint(_),
      do: {:error, InvalidEndpoint.exception(service: __MODULE__)}

    @impl Ltix.AdvantageService
    def scopes(endpoint) when endpoint in [:valid_endpoint, :other_valid_endpoint],
      do: ["https://example.com/scope/test.readonly"]
  end

  defmodule OtherService do
    @behaviour Ltix.AdvantageService

    @impl Ltix.AdvantageService
    def endpoint_from_claims(_), do: :error

    @impl Ltix.AdvantageService
    def validate_endpoint(:other_endpoint), do: :ok

    @impl Ltix.AdvantageService
    def scopes(:other_endpoint), do: ["https://example.com/scope/other.write"]
  end

  defp build_client(overrides \\ %{}) do
    defaults = %{
      token: build_token(DateTime.add(DateTime.utc_now(), 3600)),
      registration: nil,
      req_options: [],
      endpoints: %{TestService => :valid_endpoint}
    }

    struct!(Client, Map.merge(defaults, overrides))
  end

  defp build_token(expires_at) do
    %AccessToken{
      access_token: "test-token",
      token_type: "bearer",
      granted_scopes: MapSet.new([@test_scope]),
      expires_at: expires_at
    }
  end

  defp both_endpoints, do: %{TestService => :valid_endpoint, OtherService => :other_endpoint}

  defp cached_token(scope) do
    {:ok, token} =
      AccessToken.from_response(%{
        "access_token" => "cached-token",
        "token_type" => "Bearer",
        "scope" => scope
      })

    token
  end

  defp build_registration do
    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json",
        token_endpoint: "https://platform.example.com/token"
      })

    registration
  end

  defp stub_token_response do
    Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
      Req.Test.json(conn, %{
        "access_token" => "refreshed-token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => @test_scope
      })
    end)
  end

  describe "require_unexpired/1" do
    test "returns AccessTokenExpired with the expiry when the token has expired" do
      expires_at = DateTime.add(DateTime.utc_now(), -100)
      client = build_client(%{token: build_token(expires_at)})

      assert {:error, %Ltix.Errors.Security.AccessTokenExpired{expires_at: ^expires_at}} =
               Client.require_unexpired(client)
    end
  end

  describe "require_scope/2" do
    test "returns :ok for granted scope" do
      client = build_client()
      assert :ok = Client.require_scope(client, @test_scope)
    end

    test "returns error for ungranted scope" do
      client = build_client()

      assert {:error, %ScopeMismatch{scopes: ["other"]}} =
               Client.require_scope(client, "other")
    end
  end

  describe "require_any_scope/2" do
    test "returns :ok when at least one scope matches" do
      client = build_client()
      assert :ok = Client.require_any_scope(client, ["other", @test_scope])
    end

    test "returns error when no scopes match" do
      client = build_client()

      assert {:error, %ScopeMismatch{scopes: ["other1", "other2"]}} =
               Client.require_any_scope(client, ["other1", "other2"])
    end
  end

  describe "from_access_token/2 with a registration that doesn't convert" do
    test "raises InvalidOption for the registration option" do
      {:ok, token} =
        AccessToken.from_response(%{"access_token" => "cached-token", "token_type" => "Bearer"})

      assert_raise Ltix.Errors.Invalid.InvalidOption, ~r/Option :registration is invalid/, fn ->
        Client.from_access_token(token,
          registration: %BareRegistration{registration: build_registration()},
          endpoints: %{TestService => :valid_endpoint}
        )
      end
    end
  end

  describe "from_access_token/2" do
    test "raises on missing, unknown, and invalid options" do
      {:ok, token} =
        AccessToken.from_response(%{"access_token" => "cached-token", "token_type" => "Bearer"})

      registration = build_registration()

      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :registration is required", fn ->
        Client.from_access_token(token, endpoints: %{TestService => :valid_endpoint})
      end

      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :scopes is unknown", fn ->
        Client.from_access_token(token,
          registration: registration,
          endpoints: %{TestService => :valid_endpoint},
          scopes: []
        )
      end

      assert_raise Ltix.Errors.Invalid.InvalidOption, ~r/Option :req_options is invalid/, fn ->
        Client.from_access_token(token,
          registration: registration,
          endpoints: %{TestService => :valid_endpoint},
          req_options: %{}
        )
      end
    end

    test "builds client from cached token with valid endpoints" do
      registration = build_registration()

      {:ok, token} =
        AccessToken.from_response(%{
          "access_token" => "cached-token",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => @test_scope
        })

      assert {:ok, %Client{} = client} =
               Client.from_access_token(token,
                 registration: registration,
                 endpoints: %{TestService => :valid_endpoint}
               )

      assert client.token.access_token == "cached-token"
      assert MapSet.member?(client.token.granted_scopes, @test_scope)
      assert client.endpoints == %{TestService => :valid_endpoint}
    end

    test "require_all_scopes returns ScopeMismatch for each scope the token lacks" do
      registration = build_registration()

      assert {:error, %ScopeMismatch{scopes: [@other_scope]}} =
               Client.from_access_token(cached_token(@test_scope),
                 registration: registration,
                 endpoints: both_endpoints(),
                 require_all_scopes: true
               )

      assert {:error,
              %Invalid{
                errors: [
                  %ScopeMismatch{scopes: [@test_scope]},
                  %ScopeMismatch{scopes: [@other_scope]}
                ]
              }} =
               Client.from_access_token(cached_token("unrelated:scope"),
                 registration: registration,
                 endpoints: both_endpoints(),
                 require_all_scopes: true
               )

      assert {:ok, %Client{}} =
               Client.from_access_token(cached_token("#{@test_scope} #{@other_scope}"),
                 registration: registration,
                 endpoints: both_endpoints(),
                 require_all_scopes: true
               )
    end

    test "fails with InvalidEndpoint on wrong endpoint type" do
      registration = build_registration()

      {:ok, token} =
        AccessToken.from_response(%{
          "access_token" => "tok",
          "token_type" => "Bearer",
          "scope" => @test_scope
        })

      assert {:error, %InvalidEndpoint{}} =
               Client.from_access_token(token,
                 registration: registration,
                 endpoints: %{TestService => :wrong_endpoint}
               )
    end
  end

  describe "with_endpoints/3" do
    test "replaces endpoints keeping same token" do
      client = build_client()

      assert {:ok, %Client{} = new_client} =
               Client.with_endpoints(client, %{TestService => :other_valid_endpoint})

      assert new_client.endpoints == %{TestService => :other_valid_endpoint}
      assert new_client.token.access_token == client.token.access_token
      assert new_client.token.granted_scopes == client.token.granted_scopes
    end

    test "fails with InvalidEndpoint on wrong struct type" do
      client = build_client()

      assert {:error, %InvalidEndpoint{}} =
               Client.with_endpoints(client, %{TestService => :wrong_endpoint})
    end

    test "require_all_scopes returns ScopeMismatch when the token lacks an endpoint's scope" do
      client = build_client()

      assert {:error, %ScopeMismatch{scopes: [@other_scope]}} =
               Client.with_endpoints(client, both_endpoints(), require_all_scopes: true)

      assert {:ok, %Client{}} =
               Client.with_endpoints(client, %{TestService => :other_valid_endpoint},
                 require_all_scopes: true
               )
    end

    test "raises on unknown options" do
      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :unknown is unknown", fn ->
        Client.with_endpoints(build_client(), both_endpoints(), unknown: true)
      end
    end
  end

  describe "refresh/1" do
    test "re-acquires token when expired" do
      stub_token_response()
      registration = build_registration()

      client =
        build_client(%{
          registration: registration,
          token: build_token(DateTime.add(DateTime.utc_now(), -1)),
          req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
        })

      assert {:ok, %Client{} = refreshed} = Client.refresh(client)
      assert refreshed.token.access_token == "refreshed-token"
      assert refreshed.registration == registration
      assert refreshed.endpoints == client.endpoints
    end
  end

  describe "refresh telemetry" do
    setup do
      stub_token_response()
      events = for suffix <- [:start, :stop], do: [:ltix, :oauth, :refresh, suffix]
      ref = :telemetry_test.attach_event_handlers(self(), events)
      on_exit(fn -> :telemetry.detach(ref) end)

      client =
        build_client(%{
          registration: build_registration(),
          token: build_token(DateTime.add(DateTime.utc_now(), -1)),
          req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
        })

      %{client: client}
    end

    test "refresh, force_refresh, and their bangs emit a refresh span", %{client: client} do
      for refresh <- [&Client.refresh/1, &Client.force_refresh/1] do
        assert {:ok, _} = refresh.(client)
        assert_refresh_span()
      end

      for refresh <- [&Client.refresh!/1, &Client.force_refresh!/1] do
        assert %Client{} = refresh.(client)
        assert_refresh_span()
      end
    end

    test "a client that has not expired emits nothing from refresh", %{client: client} do
      assert {:ok, _} =
               Client.refresh(%{
                 client
                 | token: %{client.token | expires_at: DateTime.add(DateTime.utc_now(), 3600)}
               })

      refute_received {[:ltix, :oauth, :refresh, :start], _, _, _}
    end

    defp assert_refresh_span do
      assert_received {[:ltix, :oauth, :refresh, :start], _, _,
                       %{scopes_requested: [@test_scope]}}

      assert_received {[:ltix, :oauth, :refresh, :stop], _, %{duration: _},
                       %{
                         scopes_requested: [@test_scope],
                         scopes_granted: [@test_scope],
                         expires_in: expires_in
                       }}

      assert expires_in in 3590..3600
    end
  end

  describe "force_refresh/1" do
    test "re-acquires token regardless of expiry" do
      stub_token_response()
      registration = build_registration()

      client =
        build_client(%{
          registration: registration,
          req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
        })

      assert {:ok, %Client{} = refreshed} = Client.force_refresh(client)
      assert refreshed.token.access_token == "refreshed-token"
      assert refreshed.registration == registration
      assert refreshed.endpoints == client.endpoints
    end

    test "raises on token request failure" do
      registration = build_registration()

      Req.Test.stub(Ltix.OAuth.ClientCredentials, fn conn ->
        Plug.Conn.send_resp(conn, 400, Jason.encode!(%{"error" => "invalid_grant"}))
      end)

      client =
        build_client(%{
          registration: registration,
          req_options: [plug: {Req.Test, Ltix.OAuth.ClientCredentials}]
        })

      assert_raise Ltix.Errors.Invalid.TokenRequestFailed, fn ->
        Client.force_refresh!(client)
      end
    end
  end

  describe "request/3" do
    setup do
      %{client: build_client(%{req_options: [plug: {Req.Test, :ltix}, retry: false]})}
    end

    test "sends the request with the client's token to the service's stub", %{client: client} do
      owner = self()

      Req.Test.stub(TestService, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          owner,
          {:request, conn.method, conn.host, conn.request_path, conn.query_string, body,
           Plug.Conn.get_req_header(conn, "authorization"),
           Plug.Conn.get_req_header(conn, "accept")}
        )

        Req.Test.json(conn, %{"records" => [%{"id" => 1}]})
      end)

      assert {:ok, %Req.Response{status: 200, body: %{"records" => [%{"id" => 1}]}}} =
               Client.request(client, TestService,
                 method: :post,
                 url: "https://platform.example.com/records",
                 params: [page: 2],
                 headers: [{"accept", "application/json"}, {"authorization", "Bearer other"}],
                 json: %{"name" => "A"}
               )

      assert_received {:request, "POST", "platform.example.com", "/records", "page=2",
                       ~s({"name":"A"}), ["Bearer test-token"], ["application/json"]}
    end

    test "returns an error for a response that isn't a success", %{client: client} do
      url = "https://platform.example.com/records"

      for {status, error} <- [
            {403, Ltix.Errors.Security.AccessDenied},
            {404, Ltix.Errors.Unknown.TransportError}
          ] do
        Req.Test.stub(TestService, &Plug.Conn.send_resp(&1, status, "no"))

        assert {:error, %^error{status: ^status, url: ^url, body: "no"}} =
                 Client.request(client, TestService, url: url)
      end
    end

    test "applies the checks Ltix makes on platform requests", %{client: client} do
      Req.Test.stub(TestService, fn _conn -> flunk("the request was sent") end)

      assert {:error, %Ltix.Errors.Unknown.TransportError{} = error} =
               Client.request(client, TestService, url: "http://platform.example.com/records")

      assert Exception.message(error) =~ "HTTPS"

      assert {:error, %Ltix.Errors.Security.LocalNetworkAccessDenied{address_space: :loopback}} =
               Client.request(client, TestService,
                 url: "https://127.0.0.1/records",
                 local_network_access: :loopback
               )
    end

    test "sends the request to a local address when the client was granted access", %{
      client: client
    } do
      Req.Test.stub(TestService, &Req.Test.json(&1, %{}))
      client = %{client | local_network_access: :local}

      assert {:ok, %Req.Response{status: 200}} =
               Client.request(client, TestService, url: "https://10.0.0.5/records")
    end
  end

  describe "request_pages/3" do
    setup do
      %{client: build_client(%{req_options: [plug: {Req.Test, :ltix}, retry: false]})}
    end

    test "follows next links with the client's token", %{client: client} do
      owner = self()

      Req.Test.stub(TestService, fn conn ->
        send(
          owner,
          {:request, conn.request_path, conn.query_string,
           Plug.Conn.get_req_header(conn, "authorization"),
           Plug.Conn.get_req_header(conn, "accept")}
        )

        case conn.query_string do
          "limit=1" ->
            conn
            |> Plug.Conn.put_resp_header(
              "link",
              ~s(<https://platform.example.com/records?page=2>; rel="next")
            )
            |> Req.Test.json(%{"page" => 1})

          "page=2" ->
            Req.Test.json(conn, %{"page" => 2})
        end
      end)

      assert {:ok, pages} =
               Client.request_pages(client, TestService,
                 url: "https://platform.example.com/records",
                 params: [limit: 1],
                 headers: [{"accept", "application/json"}]
               )

      assert Enum.to_list(pages) == [{:ok, %{"page" => 1}}, {:ok, %{"page" => 2}}]

      for query <- ["limit=1", "page=2"] do
        assert_received {:request, "/records", ^query, ["Bearer test-token"],
                         ["application/json"]}
      end
    end

    test "returns the first page's error", %{client: client} do
      Req.Test.stub(TestService, &Plug.Conn.send_resp(&1, 403, "no"))

      assert {:error, %Ltix.Errors.Security.AccessDenied{status: 403}} =
               Client.request_pages(client, TestService,
                 url: "https://platform.example.com/records"
               )
    end

    test "ends the stream with a later page's error", %{client: client} do
      Req.Test.stub(TestService, fn conn ->
        case conn.request_path do
          "/records" ->
            conn
            |> Plug.Conn.put_resp_header("link", ~s(</more>; rel="next"))
            |> Req.Test.json(%{"page" => 1})

          "/more" ->
            Plug.Conn.send_resp(conn, 500, "no")
        end
      end)

      assert {:ok, pages} =
               Client.request_pages(client, TestService,
                 url: "https://platform.example.com/records"
               )

      assert [{:ok, %{"page" => 1}}, {:error, %Ltix.Errors.Unknown.TransportError{status: 500}}] =
               Enum.to_list(pages)
    end

    test "applies the client's local network access to later pages", %{client: client} do
      Req.Test.stub(TestService, fn conn ->
        case conn.request_path do
          "/records" ->
            conn
            |> Plug.Conn.put_resp_header("link", ~s(</more>; rel="next"))
            |> Req.Test.json(%{"page" => 1})

          "/more" ->
            Req.Test.json(conn, %{"page" => 2})
        end
      end)

      assert {:ok, pages} =
               Client.request_pages(%{client | local_network_access: :local}, TestService,
                 url: "https://10.0.0.5/records"
               )

      assert Enum.to_list(pages) == [{:ok, %{"page" => 1}}, {:ok, %{"page" => 2}}]
    end
  end

  describe "inspect" do
    test "leaves out the access token" do
      {:ok, token} =
        AccessToken.from_response(%{"access_token" => "secret-token", "token_type" => "Bearer"})

      {:ok, client} =
        Client.from_access_token(token,
          registration: build_registration(),
          endpoints: %{TestService => :valid_endpoint}
        )

      for value <- [token, client] do
        refute inspect(value) =~ "secret-token"
      end
    end
  end
end
