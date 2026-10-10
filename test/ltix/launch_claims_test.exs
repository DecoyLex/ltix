defmodule Ltix.LaunchClaimsTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims

  doctest Ltix.LaunchClaims

  defmodule AnalyticsClaimParser do
    use Ltix.LaunchClaims.Parser

    @impl Ltix.LaunchClaims.Parser
    def parse(%{"session_id" => session_id}), do: {:ok, {:analytics, session_id}}
  end

  # --- OIDC Claims [Sec §5.1.2] ---

  describe "from_json/2 OIDC claims [Sec §5.1.2]" do
    test "parses all OIDC standard claims" do
      json = %{
        "iss" => "https://platform.example.com",
        "sub" => "user-123",
        "aud" => "tool-client-id",
        "exp" => 1_700_000_000,
        "iat" => 1_699_999_000,
        "nonce" => "nonce-abc",
        "azp" => "tool-client-id"
      }

      assert {:ok, %LaunchClaims{} = claims} = LaunchClaims.from_json(json)
      assert claims.issuer == "https://platform.example.com"
      assert claims.subject == "user-123"
      assert claims.audience == "tool-client-id"
      assert claims.expires_at == 1_700_000_000
      assert claims.issued_at == 1_699_999_000
      assert claims.nonce == "nonce-abc"
      assert claims.authorized_party == "tool-client-id"
    end

    # [OIDC Core §5.1] profile claims, [Core §5.3.6] user identity
    test "parses OIDC profile claims" do
      json = %{
        "email" => "user@example.com",
        "name" => "Jane Doe",
        "given_name" => "Jane",
        "family_name" => "Doe",
        "middle_name" => "M",
        "picture" => "https://example.com/photo.jpg",
        "locale" => "en-US"
      }

      assert {:ok, %LaunchClaims{} = claims} = LaunchClaims.from_json(json)
      assert claims.email == "user@example.com"
      assert claims.name == "Jane Doe"
      assert claims.given_name == "Jane"
      assert claims.family_name == "Doe"
      assert claims.middle_name == "M"
      assert claims.picture == "https://example.com/photo.jpg"
      assert claims.locale == "en-US"
    end
  end

  # --- LTI Claims [Core §5.3, §5.4] ---

  describe "from_json/2 LTI claims [Core §5.3]" do
    test "parses LTI required claims" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/message_type" => "LtiResourceLinkRequest",
        "https://purl.imsglobal.org/spec/lti/claim/version" => "1.3.0",
        "https://purl.imsglobal.org/spec/lti/claim/deployment_id" => "deploy-001",
        "https://purl.imsglobal.org/spec/lti/claim/target_link_uri" =>
          "https://tool.example.com/launch"
      }

      assert {:ok, %LaunchClaims{} = claims} = LaunchClaims.from_json(json)
      assert claims.message_type == "LtiResourceLinkRequest"
      assert claims.version == "1.3.0"
      assert claims.deployment_id == "deploy-001"
      assert claims.target_link_uri == "https://tool.example.com/launch"
    end

    # [Core §5.4.3] role_scope_mentor
    test "parses role_scope_mentor" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor" => [
          "user-001",
          "user-002"
        ]
      }

      assert {:ok, %LaunchClaims{role_scope_mentor: mentees}} = LaunchClaims.from_json(json)
      assert mentees == ["user-001", "user-002"]
    end
  end

  # --- Role Parsing [Core §A.2] ---

  describe "from_json/2 roles [Core §5.3.7]" do
    test "defaults roles to empty list when absent" do
      assert {:ok, %LaunchClaims{roles: [], unrecognized_roles: []}} =
               LaunchClaims.from_json(%{})
    end
  end

  # --- Nested Claim Structs ---

  describe "from_json/2 nested claims" do
    # [Core §5.4] missing optional nested claims default to nil
    test "missing optional nested claims default to nil" do
      assert {:ok, %LaunchClaims{} = claims} = LaunchClaims.from_json(%{})
      assert claims.context == nil
      assert claims.resource_link == nil
      assert claims.launch_presentation == nil
      assert claims.tool_platform == nil
      assert claims.lis == nil
    end

    test "invalid resource_link propagates error" do
      json = %{
        "https://purl.imsglobal.org/spec/lti/claim/resource_link" => %{
          "title" => "No ID"
        }
      }

      assert {:error, error} = LaunchClaims.from_json(json)
      assert Exception.message(error) =~ "resource_link.id"
    end
  end

  # --- Extensions [Core §5.4.7] ---

  describe "from_json/2 extensions [Core §5.4.7]" do
    test "extension parsers can be modules implementing the claim parser behaviour" do
      json = %{"https://example.com/analytics" => %{"session_id" => "abc"}}

      assert {:ok, %LaunchClaims{extensions: extensions}} =
               LaunchClaims.from_json(json,
                 claim_parsers: %{"https://example.com/analytics" => AnalyticsClaimParser}
               )

      assert extensions["https://example.com/analytics"] == {:analytics, "abc"}
    end

    test "raises when a claim parser is not a parser module or 1-arity function" do
      for parser <- [Enum, "parser", fn _value, _other -> {:ok, nil} end] do
        assert_raise Ltix.Errors.Invalid.InvalidOption,
                     ~r/Option :claim_parsers is invalid, parsers must be modules/,
                     fn -> LaunchClaims.from_json(%{}, claim_parsers: %{"name" => parser}) end
      end
    end

    test "claim parser failures are returned as invalid claim errors with the claim name" do
      key = "https://example.com/bad"

      for {reason, message} <- [
            {"missing session_id", "missing session_id"},
            {:no_session, ":no_session"},
            {{:unexpected, 1}, "{:unexpected, 1}"},
            {RuntimeError.exception("parse failed"), "parse failed"}
          ] do
        assert {:error,
                %Ltix.Errors.Invalid.InvalidClaim{claim: ^key, value: "value", message: ^message}} =
                 LaunchClaims.from_json(%{key => "value"},
                   claim_parsers: %{key => fn "value" -> {:error, reason} end}
                 )
      end

      assert {:error, error} =
               LaunchClaims.from_json(%{"name" => 1},
                 claim_parsers: %{"name" => fn 1 -> {:error, "must be a string"} end}
               )

      assert Exception.message(error) == "Invalid LTI claim name: must be a string (got 1)"
    end

    test "claim parsers run only for claims present in the token" do
      parser = fn value ->
        send(self(), {:parsed, value})
        {:ok, value}
      end

      assert {:ok, %LaunchClaims{name: nil, extensions: extensions}} =
               LaunchClaims.from_json(%{"https://example.com/null" => nil},
                 claim_parsers: %{"name" => parser, "https://example.com/null" => parser}
               )

      assert extensions == %{"https://example.com/null" => nil}
      assert_received {:parsed, nil}
      refute_received {:parsed, _}
    end
  end

  # --- Errors ---

  describe "from_json/2 errors" do
    test "raises on unknown and invalid options" do
      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :claim_parser is unknown", fn ->
        LaunchClaims.from_json(%{}, claim_parser: %{})
      end

      assert_raise Ltix.Errors.Invalid.InvalidOption, ~r/Option :role_parsers is invalid/, fn ->
        LaunchClaims.from_json(%{}, role_parsers: [:instructor])
      end
    end

    test "a single invalid claim is returned on its own" do
      assert {:error, %Ltix.Errors.Invalid.InvalidClaim{claim: "iss", value: 1}} =
               LaunchClaims.from_json(%{"iss" => 1})

      assert {:error, %Ltix.Errors.Invalid.InvalidClaim{claim: "message_type", value: 1}} =
               LaunchClaims.from_json(%{
                 "https://purl.imsglobal.org/spec/lti/claim/message_type" => 1
               })
    end

    test "several invalid claims are described without stack frames" do
      assert {:error, %Ltix.Errors.Invalid{} = error} =
               LaunchClaims.from_json(%{"iss" => 1, "sub" => 2})

      message = Exception.message(error)
      assert message =~ "Invalid LTI claim iss"
      assert message =~ "Invalid LTI claim sub"
      refute message =~ ~r/\.exs?:\d+/
    end
  end
end
