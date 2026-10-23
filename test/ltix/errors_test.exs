defmodule Ltix.ErrorsTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors

  alias Ltix.Errors.Invalid.CollectionTooLarge
  alias Ltix.Errors.Invalid.CoupledLineItem
  alias Ltix.Errors.Invalid.DeploymentNotFound
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.InvalidContentItem
  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.InvalidMessageType
  alias Ltix.Errors.Invalid.LineItemNotAccepted
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Invalid.MissingParameter
  alias Ltix.Errors.Invalid.RegistrationNotFound
  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Invalid.TokenRequestFailed
  alias Ltix.Errors.Security.AccessDenied
  alias Ltix.Errors.Security.AccessTokenExpired
  alias Ltix.Errors.Security.AlgorithmNotAllowed
  alias Ltix.Errors.Security.AudienceMismatch
  alias Ltix.Errors.Security.AuthenticationFailed
  alias Ltix.Errors.Security.IssuerMismatch
  alias Ltix.Errors.Security.KidNotFound
  alias Ltix.Errors.Security.SignatureInvalid
  alias Ltix.Errors.Security.TokenNotYetValid
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.Errors.Unknown.Unknown

  doctest Ltix.Errors

  describe "status_code/1" do
    test "security errors return 401" do
      error = SignatureInvalid.exception()
      assert Errors.status_code(error) == 401
    end

    test "unknown errors return 500" do
      error = Unknown.exception(error: "something broke")
      assert Errors.status_code(error) == 500
    end

    test "error class aggregates return correct codes" do
      assert Errors.status_code(Errors.Invalid.exception(errors: [])) == 400
      assert Errors.status_code(Errors.Security.exception(errors: [])) == 401
      assert Errors.status_code(Errors.Unknown.exception(errors: [])) == 500
    end

    test "other exceptions return 500" do
      assert Errors.status_code(%RuntimeError{message: "boom"}) == 500
    end
  end

  if Code.ensure_loaded?(Plug) do
    describe "Plug.Exception" do
      test "invalid errors return 400" do
        error = MissingClaim.exception(claim: "sub")
        assert Plug.Exception.status(error) == 400
      end
    end
  end

  describe "Invalid error modules" do
    test "MissingClaim includes claim name in message" do
      error = MissingClaim.exception(claim: "version")
      assert Exception.message(error) =~ "version"
    end

    test "InvalidClaim includes claim name and value in message" do
      error =
        InvalidClaim.exception(
          claim: "message_type",
          value: "wrong"
        )

      assert Exception.message(error) =~ "message_type"
      assert Exception.message(error) =~ "wrong"
    end

    test "MissingParameter includes parameter name" do
      error =
        MissingParameter.exception(parameter: "iss")

      assert Exception.message(error) =~ "iss"
    end

    test "RegistrationNotFound includes issuer and client_id" do
      error =
        RegistrationNotFound.exception(
          issuer: "https://platform.example.com",
          client_id: "tool-123"
        )

      assert Exception.message(error) =~ "https://platform.example.com"
      assert Exception.message(error) =~ "tool-123"
    end

    test "DeploymentNotFound includes deployment_id" do
      error = DeploymentNotFound.exception(deployment_id: "deploy-456")
      assert Exception.message(error) =~ "deploy-456"
    end

    test "ServiceNotAvailable includes service name" do
      error =
        ServiceNotAvailable.exception(service: Ltix.MembershipsService)

      assert Exception.message(error) =~ "MembershipsService"
    end

    test "TokenRequestFailed with OAuth error includes error code" do
      error =
        TokenRequestFailed.exception(
          error: "invalid_grant",
          error_description: "bad grant"
        )

      assert Exception.message(error) ==
               "OAuth token request failed: invalid_grant. bad grant"

      assert Exception.message(%{error | error_description: nil}) ==
               "OAuth token request failed: invalid_grant"
    end

    test "TokenRequestFailed with HTTP status includes status code" do
      error =
        TokenRequestFailed.exception(
          status: 500,
          body: "server error"
        )

      assert Exception.message(error) == "OAuth token request failed (HTTP 500)"
    end

    test "MalformedResponse includes service and reason" do
      error =
        MalformedResponse.exception(
          service: Ltix.MembershipsService,
          reason: "invalid JSON"
        )

      assert Exception.message(error) =~ "MembershipsService"
      assert Exception.message(error) =~ "invalid JSON"
    end

    test "CollectionTooLarge includes service, limit option, count, and max" do
      error =
        CollectionTooLarge.exception(
          service: Ltix.MembershipsService,
          option: :max_members,
          count: 15_000,
          max: 10_000
        )

      assert Exception.message(error) =~ "MembershipsService"
      assert Exception.message(error) =~ "max_members"
      assert Exception.message(error) =~ "15000"
      assert Exception.message(error) =~ "10000"
      assert Exception.message(error) =~ "higher limit"
    end

    test "ScopeMismatch includes scopes" do
      error =
        ScopeMismatch.exception(
          scopes: ["https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"],
          granted_scopes: []
        )

      assert Exception.message(error) =~ "contextmembership.readonly"
    end

    test "InvalidEndpoint includes service name" do
      error =
        InvalidEndpoint.exception(service: Ltix.MembershipsService)

      assert Exception.message(error) =~ "MembershipsService"
    end
  end

  describe "Security error modules" do
    test "TokenNotYetValid includes the claim" do
      error = TokenNotYetValid.exception(claim: "nbf")
      assert Exception.message(error) =~ "nbf"
    end

    test "IssuerMismatch includes expected and actual values" do
      error =
        IssuerMismatch.exception(
          expected: "https://platform.example.com",
          actual: "https://evil.example.com"
        )

      assert Exception.message(error) =~ "https://platform.example.com"
      assert Exception.message(error) =~ "https://evil.example.com"
    end

    test "AudienceMismatch includes the claim, the expected client_id, and the actual audience" do
      error =
        AudienceMismatch.exception(
          claim: "aud",
          expected: "my-client-id",
          actual: ["other-client"]
        )

      assert Exception.message(error) ==
               ~s(Audience mismatch: expected my-client-id in aud ["other-client"])
    end

    test "AlgorithmNotAllowed includes algorithm" do
      error =
        AlgorithmNotAllowed.exception(algorithm: "HS256")

      assert Exception.message(error) =~ "HS256"
    end

    test "KidNotFound includes kid value" do
      error =
        KidNotFound.exception(kid: "unknown-key-id")

      assert Exception.message(error) ==
               "Key not found in the platform's key set for kid: unknown-key-id"
    end

    test "AccessDenied includes URL and status" do
      error =
        AccessDenied.exception(
          url: "https://lms.example.com/memberships",
          status: 403,
          body: "Forbidden"
        )

      assert Exception.message(error) =~ "https://lms.example.com/memberships"
      assert Exception.message(error) =~ "403"
    end

    test "AccessTokenExpired includes expiry time" do
      expires_at = ~U[2026-03-08 12:00:00Z]

      error =
        AccessTokenExpired.exception(expires_at: expires_at)

      assert Exception.message(error) =~ "2026-03-08"
      assert Exception.message(error) =~ "Client.refresh/1"
    end
  end

  describe "Deep linking and Advantage error modules" do
    test "CoupledLineItem includes line_item_url" do
      error =
        CoupledLineItem.exception(line_item_url: "https://lms.example.com/lineitems/1")

      assert Exception.message(error) =~ "https://lms.example.com/lineitems/1"
      assert Exception.message(error) =~ "coupled"
    end

    test "InvalidMessageType includes message_type" do
      error =
        InvalidMessageType.exception(message_type: "LtiResourceLinkRequest")

      assert Exception.message(error) =~ "LtiResourceLinkRequest"
    end

    test "LineItemNotAccepted includes the item index" do
      error = LineItemNotAccepted.exception(index: 2)

      assert Exception.message(error) =~ "index 2"
    end

    test "InvalidContentItem includes the item index and value" do
      error =
        InvalidContentItem.exception(
          index: 2,
          value: "https://example.com",
          reason: "is not a content item"
        )

      assert Exception.message(error) ==
               ~s(Content item at index 2 is not a content item, got "https://example.com")
    end
  end

  describe "Security error modules (additional)" do
    test "AuthenticationFailed with description" do
      error =
        AuthenticationFailed.exception(
          error: "access_denied",
          error_description: "User cancelled",
          error_uri: nil
        )

      assert Exception.message(error) ==
               "Platform authentication failed: access_denied. User cancelled"
    end

    test "AuthenticationFailed without description" do
      error =
        AuthenticationFailed.exception(
          error: "access_denied",
          error_description: nil,
          error_uri: nil
        )

      assert Exception.message(error) ==
               "Platform authentication failed: access_denied"

      blank = %{error | error_description: ""}

      assert Exception.message(blank) ==
               "Platform authentication failed: access_denied"
    end
  end

  describe "Unknown error modules" do
    test "Unknown wraps arbitrary string error" do
      error = Unknown.exception(error: "something went wrong")
      assert Exception.message(error) =~ "something went wrong"
    end

    test "Unknown wraps non-string error" do
      error = Unknown.exception(error: {:connection_refused, :econnrefused})
      assert Exception.message(error) =~ "connection_refused"
    end

    test "TransportError with status includes HTTP status and URL" do
      error =
        TransportError.exception(
          status: 502,
          body: nil,
          url: "https://platform.example.com/jwks"
        )

      assert Exception.message(error) =~ "502"
      assert Exception.message(error) =~ "https://platform.example.com/jwks"
    end

    test "TransportError includes the URL when there is one" do
      assert Exception.message(
               TransportError.exception(body: "timeout", url: "https://lms.example.com/jwks")
             ) ==
               "Transport error for https://lms.example.com/jwks: timeout"

      assert Exception.message(TransportError.exception(status: 502)) == "HTTP 502"
    end

    test "TransportError without status with non-string body" do
      error =
        TransportError.exception(
          status: nil,
          body: %{"error" => "timeout"},
          url: nil
        )

      assert Exception.message(error) =~ "timeout"
    end
  end

  describe "MalformedResponse additional branches" do
    test "MalformedResponse without service" do
      error = MalformedResponse.exception(service: nil, reason: "invalid JSON")
      assert Exception.message(error) == "Malformed response: invalid JSON"
    end
  end
end
