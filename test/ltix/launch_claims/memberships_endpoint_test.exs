defmodule Ltix.LaunchClaims.MembershipsEndpointTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.LaunchClaims.MembershipsEndpoint

  doctest Ltix.LaunchClaims.MembershipsEndpoint

  describe "from_json/1" do
    test "returns an error with the claim's key when the claim is not an object" do
      assert {:error,
              %InvalidClaim{
                claim: "https://purl.imsglobal.org/spec/lti-nrps/claim/namesroleservice"
              }} = MembershipsEndpoint.from_json("https://platform.example.com/api/memberships")
    end
  end

  describe "new/1" do
    test "rejects a URL that is not an absolute HTTPS URL" do
      for url <- ["http://lms.example.com/memberships", "/memberships", "not a url"] do
        assert {:error,
                %InvalidField{
                  struct: MembershipsEndpoint,
                  field: :context_memberships_url,
                  value: ^url
                }} =
                 MembershipsEndpoint.new(url)
      end
    end

    test "rejects a missing URL" do
      for url <- [nil, ""] do
        assert {:error, %InvalidField{field: :context_memberships_url, reason: :required}} =
                 MembershipsEndpoint.new(url)
      end
    end
  end

  describe "new!/1" do
    test "raises on an invalid URL" do
      assert_raise InvalidField, fn -> MembershipsEndpoint.new!("http://lms.example.com") end
    end
  end
end
