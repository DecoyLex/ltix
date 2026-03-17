defmodule Ltix.OAuth.ClientTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.OAuth.AccessToken
  alias Ltix.OAuth.Client

  doctest Client

  @test_scope "https://example.com/scope/test.readonly"

  defmodule TestService do
    @behaviour Ltix.AdvantageService

    @impl Ltix.AdvantageService
    def endpoint_from_claims(_), do: :error

    @impl Ltix.AdvantageService
    def validate_endpoint(:valid_endpoint), do: :ok

    def validate_endpoint(_),
      do: {:error, InvalidEndpoint.exception(service: __MODULE__, spec_ref: "test")}

    @impl Ltix.AdvantageService
    def scopes(:valid_endpoint),
      do: ["https://example.com/scope/test.readonly"]
  end

  defp build_client(overrides \\ %{}) do
    defaults = %{
      access_token: "test-token",
      expires_at: DateTime.add(DateTime.utc_now(), 3600),
      scopes: MapSet.new([@test_scope]),
      registration: nil,
      req_options: [],
      endpoints: %{TestService => :valid_endpoint}
    }

    struct!(Client, Map.merge(defaults, overrides))
  end

  defp build_registration do
    tool_jwk = Ltix.JWK.generate()

    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks.json",
        token_endpoint: "https://platform.example.com/token",
        tool_jwk: tool_jwk
      })

    registration
  end

  defp stub_token_response do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "access_token" => "refreshed-token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => @test_scope
      })
    end)
  end

  describe "expired?/1" do
    test "returns false when token is fresh" do
      client = build_client(%{expires_at: DateTime.add(DateTime.utc_now(), 3600)})
      refute Client.expired?(client)
    end

    test "returns true when within 60s buffer of expiry" do
      client = build_client(%{expires_at: DateTime.add(DateTime.utc_now(), 30)})
      assert Client.expired?(client)
    end

    test "returns true when token is already past expiry" do
      client = build_client(%{expires_at: DateTime.add(DateTime.utc_now(), -100)})
      assert Client.expired?(client)
    end
  end

  describe "has_scope?/2" do
    test "returns true for granted scope" do
      client = build_client()
      assert Client.has_scope?(client, @test_scope)
    end

    test "returns false for ungranted scope" do
      client = build_client()
      refute Client.has_scope?(client, "https://example.com/scope/other")
    end
  end

  describe "require_scope/2" do
    test "returns :ok for granted scope" do
      client = build_client()
      assert :ok = Client.require_scope(client, @test_scope)
    end

    test "returns error for ungranted scope" do
      client = build_client()

      assert {:error, %ScopeMismatch{scope: "other"}} =
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

      assert {:error, %ScopeMismatch{}} =
               Client.require_any_scope(client, ["other1", "other2"])
    end
  end

  describe "from_access_token/2" do
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

      assert client.access_token == "cached-token"
      assert MapSet.member?(client.scopes, @test_scope)
      assert client.endpoints == %{TestService => :valid_endpoint}
    end

    test "fails with ScopeMismatch when token lacks needed scopes" do
      registration = build_registration()

      {:ok, token} =
        AccessToken.from_response(%{
          "access_token" => "no-scope-token",
          "token_type" => "Bearer",
          "scope" => "unrelated:scope"
        })

      assert {:error, %ScopeMismatch{}} =
               Client.from_access_token(token,
                 registration: registration,
                 endpoints: %{TestService => :valid_endpoint}
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

  describe "with_endpoints/2" do
    test "swaps endpoints keeping same token" do
      client = build_client()

      assert {:ok, %Client{} = new_client} =
               Client.with_endpoints(client, %{TestService => :valid_endpoint})

      assert new_client.access_token == client.access_token
      assert new_client.scopes == client.scopes
    end

    test "fails with InvalidEndpoint on wrong struct type" do
      client = build_client()

      assert {:error, %InvalidEndpoint{}} =
               Client.with_endpoints(client, %{TestService => :wrong_endpoint})
    end

    test "fails with ScopeMismatch when token lacks new endpoint scopes" do
      client = build_client(%{scopes: MapSet.new(["unrelated:scope"])})

      assert {:error, %ScopeMismatch{}} =
               Client.with_endpoints(client, %{TestService => :valid_endpoint})
    end
  end

  describe "refresh/1" do
    test "re-acquires token and returns new client" do
      stub_token_response()
      registration = build_registration()

      client =
        build_client(%{
          registration: registration,
          req_options: [plug: {Req.Test, __MODULE__}]
        })

      assert {:ok, %Client{} = refreshed} = Client.refresh(client)
      assert refreshed.access_token == "refreshed-token"
      assert refreshed.registration == registration
      assert refreshed.endpoints == client.endpoints
    end

    test "refresh!/1 raises on error" do
      registration = build_registration()

      Req.Test.stub(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 400, Jason.encode!(%{"error" => "invalid_grant"}))
      end)

      client =
        build_client(%{
          registration: registration,
          req_options: [plug: {Req.Test, __MODULE__}]
        })

      assert_raise Ltix.Errors.Invalid.TokenRequestFailed, fn -> Client.refresh!(client) end
    end
  end
end
