defmodule Ltix.ErrorsTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors

  alias Ltix.Errors.Invalid.DeploymentNotFound
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.InvalidEndpoint
  alias Ltix.Errors.Invalid.InvalidJson
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Errors.Invalid.MissingParameter
  alias Ltix.Errors.Invalid.RegistrationNotFound
  alias Ltix.Errors.Invalid.RosterTooLarge
  alias Ltix.Errors.Invalid.ScopeMismatch
  alias Ltix.Errors.Invalid.ServiceNotAvailable
  alias Ltix.Errors.Invalid.TokenRequestFailed
  alias Ltix.Errors.Security.AccessDenied
  alias Ltix.Errors.Security.AccessTokenExpired
  alias Ltix.Errors.Security.AlgorithmNotAllowed
  alias Ltix.Errors.Security.AudienceMismatch
  alias Ltix.Errors.Security.IssuerMismatch
  alias Ltix.Errors.Security.KidMissing
  alias Ltix.Errors.Security.KidNotFound
  alias Ltix.Errors.Security.NonceMissing
  alias Ltix.Errors.Security.NonceNotFound
  alias Ltix.Errors.Security.NonceReused
  alias Ltix.Errors.Security.SignatureInvalid
  alias Ltix.Errors.Security.StateMismatch
  alias Ltix.Errors.Security.TokenExpired

  describe "error classes" do
    test "invalid errors produce Invalid class" do
      error = MissingClaim.exception(claim: "version", spec_ref: "Core §5.3.2")
      class = Errors.to_class([error])
      assert %Errors.Invalid{} = class
    end

    test "Advantage service invalid errors produce Invalid class" do
      error = ServiceNotAvailable.exception(service: Ltix.MembershipsService, spec_ref: "")
      assert %Errors.Invalid{} = Errors.to_class([error])
    end

    test "security errors produce Security class" do
      error = SignatureInvalid.exception(spec_ref: "Sec §5.1.3 step 1")
      class = Errors.to_class([error])
      assert %Errors.Security{} = class
    end

    test "Advantage service security errors produce Security class" do
      error = AccessDenied.exception(service: Ltix.MembershipsService, status: 403, spec_ref: "")
      assert %Errors.Security{} = Errors.to_class([error])
    end

    test "unknown errors produce Unknown class" do
      error = Errors.Unknown.Unknown.exception(error: "something unexpected")
      class = Errors.to_class([error])
      assert %Errors.Unknown{} = class
    end
  end

  describe "Invalid error modules" do
    test "MissingClaim includes claim name and spec ref in message" do
      error = MissingClaim.exception(claim: "version", spec_ref: "Core §5.3.2")
      assert Exception.message(error) =~ "version"
      assert Exception.message(error) =~ "Core §5.3.2"
    end

    test "InvalidClaim includes claim name, value, and spec ref in message" do
      error =
        InvalidClaim.exception(
          claim: "message_type",
          value: "wrong",
          spec_ref: "Core §5.3.1"
        )

      assert Exception.message(error) =~ "message_type"
      assert Exception.message(error) =~ "wrong"
      assert Exception.message(error) =~ "Core §5.3.1"
    end

    test "InvalidJson includes spec ref in message" do
      error = InvalidJson.exception(spec_ref: "Cert §6.1.1")
      assert Exception.message(error) =~ "Cert §6.1.1"
    end

    test "MissingParameter includes parameter name and spec ref" do
      error =
        MissingParameter.exception(parameter: "iss", spec_ref: "Sec §5.1.1.1")

      assert Exception.message(error) =~ "iss"
      assert Exception.message(error) =~ "Sec §5.1.1.1"
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

    test "ServiceNotAvailable includes service name and spec ref" do
      error =
        ServiceNotAvailable.exception(
          service: Ltix.MembershipsService,
          spec_ref: "NRPS §3.6.1.1"
        )

      assert Exception.message(error) =~ "MembershipsService"
      assert Exception.message(error) =~ "NRPS §3.6.1.1"
    end

    test "TokenRequestFailed with OAuth error includes error code [Sec §4.1]" do
      error =
        TokenRequestFailed.exception(
          error: "invalid_grant",
          error_description: "bad grant",
          spec_ref: "Sec §4.1"
        )

      assert Exception.message(error) =~ "invalid_grant"
      assert Exception.message(error) =~ "Sec §4.1"
    end

    test "TokenRequestFailed with HTTP status includes status code [Sec §4.1]" do
      error =
        TokenRequestFailed.exception(
          status: 500,
          body: "server error",
          spec_ref: "Sec §4.1"
        )

      assert Exception.message(error) =~ "500"
    end

    test "MalformedResponse includes service and reason" do
      error =
        MalformedResponse.exception(
          service: Ltix.MembershipsService,
          reason: "invalid JSON",
          spec_ref: "NRPS §2.1"
        )

      assert Exception.message(error) =~ "MembershipsService"
      assert Exception.message(error) =~ "invalid JSON"
    end

    test "RosterTooLarge includes count and max" do
      error = RosterTooLarge.exception(count: 15_000, max: 10_000, spec_ref: "")

      assert Exception.message(error) =~ "15000"
      assert Exception.message(error) =~ "10000"
      assert Exception.message(error) =~ "stream_members/2"
      assert Exception.message(error) =~ "higher limit"
    end

    test "ScopeMismatch includes scope [Sec §4.1]" do
      error =
        ScopeMismatch.exception(
          scope: "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly",
          granted_scopes: [],
          spec_ref: "Sec §4.1"
        )

      assert Exception.message(error) =~ "contextmembership.readonly"
    end

    test "InvalidEndpoint includes service name" do
      error =
        InvalidEndpoint.exception(
          service: Ltix.MembershipsService,
          spec_ref: "Core §6.1"
        )

      assert Exception.message(error) =~ "MembershipsService"
    end
  end

  describe "Security error modules" do
    test "SignatureInvalid includes spec ref" do
      error = SignatureInvalid.exception(spec_ref: "Sec §5.1.3 step 1")
      assert Exception.message(error) =~ "Sec §5.1.3 step 1"
    end

    test "TokenExpired includes spec ref" do
      error = TokenExpired.exception(spec_ref: "Sec §5.1.3 step 7")
      assert Exception.message(error) =~ "Sec §5.1.3 step 7"
    end

    test "IssuerMismatch includes expected and actual values" do
      error =
        IssuerMismatch.exception(
          expected: "https://platform.example.com",
          actual: "https://evil.example.com",
          spec_ref: "Sec §5.1.3 step 2"
        )

      assert Exception.message(error) =~ "https://platform.example.com"
      assert Exception.message(error) =~ "https://evil.example.com"
    end

    test "AudienceMismatch includes expected client_id and actual audience" do
      error =
        AudienceMismatch.exception(
          expected: "my-client-id",
          actual: ["other-client"],
          spec_ref: "Sec §5.1.3 step 3"
        )

      assert Exception.message(error) =~ "my-client-id"
    end

    test "AlgorithmNotAllowed includes algorithm" do
      error =
        AlgorithmNotAllowed.exception(
          algorithm: "HS256",
          spec_ref: "Sec §5.1.3 step 6"
        )

      assert Exception.message(error) =~ "HS256"
    end

    test "NonceMissing includes spec ref" do
      error = NonceMissing.exception(spec_ref: "Sec §5.1.3 step 9")
      assert Exception.message(error) =~ "nonce"
    end

    test "NonceReused includes spec ref" do
      error = NonceReused.exception(spec_ref: "Sec §5.1.3 step 9")
      assert Exception.message(error) =~ "nonce"
    end

    test "NonceNotFound includes spec ref" do
      error = NonceNotFound.exception(spec_ref: "Sec §5.1.3 step 9")
      assert Exception.message(error) =~ "nonce"
    end

    test "StateMismatch includes spec ref" do
      error = StateMismatch.exception(spec_ref: "Sec §7.3.1")
      assert Exception.message(error) =~ "state"
    end

    test "KidMissing includes spec ref" do
      error = KidMissing.exception(spec_ref: "Cert §6.1.1")
      assert Exception.message(error) =~ "kid"
    end

    test "KidNotFound includes kid value" do
      error =
        KidNotFound.exception(kid: "unknown-key-id", spec_ref: "Cert §6.1.1")

      assert Exception.message(error) =~ "unknown-key-id"
    end

    test "AccessDenied includes service and status [Sec §4.1]" do
      error =
        AccessDenied.exception(
          service: Ltix.MembershipsService,
          status: 403,
          body: "Forbidden",
          spec_ref: "Sec §4.1"
        )

      assert Exception.message(error) =~ "MembershipsService"
      assert Exception.message(error) =~ "403"
    end

    test "AccessTokenExpired includes expiry time [Sec §7.1]" do
      expires_at = ~U[2026-03-08 12:00:00Z]

      error =
        AccessTokenExpired.exception(
          expires_at: expires_at,
          spec_ref: "Sec §7.1"
        )

      assert Exception.message(error) =~ "2026-03-08"
      assert Exception.message(error) =~ "Client.refresh/1"
    end
  end

  describe "Unknown error modules" do
    test "Unknown wraps arbitrary error" do
      error = Errors.Unknown.Unknown.exception(error: "something went wrong")
      assert Exception.message(error) =~ "something went wrong"
    end
  end
end
