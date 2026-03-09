defmodule Ltix.OAuth.AccessTokenTest do
  use ExUnit.Case, async: true

  alias Ltix.OAuth.AccessToken

  doctest AccessToken

  @now ~U[2025-01-01 00:00:00Z]

  @valid_response %{
    "access_token" => "test-token-123",
    "token_type" => "Bearer",
    "expires_in" => 3600,
    "scope" => "scope:read scope:write"
  }

  describe "from_response/2" do
    test "parses all fields from a complete response" do
      assert {:ok, token} = AccessToken.from_response(@valid_response, now: @now)

      assert token.access_token == "test-token-123"
      assert token.token_type == "bearer"
      assert token.granted_scopes == ["scope:read", "scope:write"]
      assert token.expires_at == ~U[2025-01-01 01:00:00Z]
    end

    test "normalizes token_type to lowercase" do
      for type <- ["Bearer", "bearer", "BEARER"] do
        assert {:ok, token} =
                 AccessToken.from_response(%{@valid_response | "token_type" => type}, now: @now)

        assert token.token_type == "bearer"
      end
    end

    test "defaults expires_in to 3600 when absent" do
      response = Map.delete(@valid_response, "expires_in")

      assert {:ok, token} = AccessToken.from_response(response, now: @now)
      assert token.expires_at == ~U[2025-01-01 01:00:00Z]
    end

    test "computes expires_at from custom expires_in" do
      response = %{@valid_response | "expires_in" => 600}

      assert {:ok, token} = AccessToken.from_response(response, now: @now)
      assert token.expires_at == ~U[2025-01-01 00:10:00Z]
    end

    test "falls back to requested_scopes when scope is absent" do
      response = Map.delete(@valid_response, "scope")

      assert {:ok, token} =
               AccessToken.from_response(response,
                 now: @now,
                 requested_scopes: ["scope:read"]
               )

      assert token.granted_scopes == ["scope:read"]
    end

    test "uses empty list when scope absent and no requested_scopes" do
      response = Map.delete(@valid_response, "scope")

      assert {:ok, token} = AccessToken.from_response(response, now: @now)
      assert token.granted_scopes == []
    end

    test "splits scope string on spaces" do
      response = %{@valid_response | "scope" => "a b c"}

      assert {:ok, token} = AccessToken.from_response(response, now: @now)
      assert token.granted_scopes == ["a", "b", "c"]
    end

    test "returns error when access_token is missing" do
      response = Map.delete(@valid_response, "access_token")

      assert {:error, error} = AccessToken.from_response(response, now: @now)
      assert Exception.message(error) =~ "missing access_token or token_type"
    end

    test "returns error when token_type is missing" do
      response = Map.delete(@valid_response, "token_type")

      assert {:error, error} = AccessToken.from_response(response, now: @now)
      assert Exception.message(error) =~ "missing access_token or token_type"
    end

    test "returns error when access_token is not a string" do
      response = %{@valid_response | "access_token" => 123}

      assert {:error, _error} = AccessToken.from_response(response, now: @now)
    end
  end
end
