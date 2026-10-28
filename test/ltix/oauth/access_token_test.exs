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
    test "raises on unknown and invalid options" do
      assert_raise ArgumentError, "Option :scopes is unknown", fn ->
        AccessToken.from_response(@valid_response, scopes: [])
      end

      assert_raise ArgumentError, ~r/Option :now is invalid/, fn ->
        AccessToken.from_response(@valid_response, now: "2025-01-01T00:00:00Z")
      end
    end
  end

  describe "expired?/1" do
    test "returns true within 60 seconds of expiry" do
      assert AccessToken.expired?(%AccessToken{expires_at: DateTime.add(DateTime.utc_now(), 59)})
      refute AccessToken.expired?(%AccessToken{expires_at: DateTime.add(DateTime.utc_now(), 62)})
    end
  end

  describe "to_map/1 and from_map/1" do
    test "restore a token from its JSON-encoded map" do
      {:ok, token} = AccessToken.from_response(@valid_response, now: @now)
      json = Ltix.AppConfig.json_library!()

      stored =
        token
        |> AccessToken.to_map()
        |> json.encode!()
        |> IO.iodata_to_binary()

      assert {:ok, ^token} = AccessToken.from_map(json.decode!(stored))
    end

    test "restore a token built without an issue time" do
      token = %AccessToken{
        access_token: "test-token-123",
        token_type: "bearer",
        granted_scopes: MapSet.new(),
        expires_at: @now
      }

      assert {:ok, ^token} = AccessToken.from_map(AccessToken.to_map(token))
    end

    test "from_map/1 returns InvalidField for a missing or malformed field" do
      valid = AccessToken.to_map(elem(AccessToken.from_response(@valid_response, now: @now), 1))

      for {field, value} <- [
            {"access_token", nil},
            {"access_token", 123},
            {"expires_at", nil},
            {"expires_at", "tomorrow"},
            {"expires_at", 1_735_693_200},
            {"scope", ["scope:read"]}
          ] do
        assert {:error, %Ltix.Errors.Invalid.InvalidField{struct: AccessToken}} =
                 AccessToken.from_map(Map.put(valid, field, value))
      end
    end

    test "from_map/1 leaves the access token out of errors" do
      assert {:error, error} = AccessToken.from_map(%{"access_token" => "secret-token"})
      refute inspect(error) =~ "secret-token"
    end
  end
end
