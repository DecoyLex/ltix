defmodule Ltix.ErrorsTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors

  alias Ltix.Errors.Invalid.{
    DeploymentNotFound,
    InvalidClaim,
    InvalidJson,
    MissingClaim,
    MissingParameter,
    RegistrationNotFound
  }

  alias Ltix.Errors.Security.{
    AlgorithmNotAllowed,
    AudienceMismatch,
    IssuerMismatch,
    KidMissing,
    KidNotFound,
    NonceMissing,
    NonceNotFound,
    NonceReused,
    SignatureInvalid,
    StateMismatch,
    TokenExpired
  }

  describe "error classes" do
    test "invalid errors produce Invalid class" do
      error = MissingClaim.exception(claim: "version", spec_ref: "Core §5.3.2")
      class = Errors.to_class([error])
      assert %Errors.Invalid{} = class
    end

    test "security errors produce Security class" do
      error = SignatureInvalid.exception(spec_ref: "Sec §5.1.3 step 1")
      class = Errors.to_class([error])
      assert %Errors.Security{} = class
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
  end

  describe "Unknown error modules" do
    test "Unknown wraps arbitrary error" do
      error = Errors.Unknown.Unknown.exception(error: "something went wrong")
      assert Exception.message(error) =~ "something went wrong"
    end
  end
end
