defmodule Ltix.MembershipsService.EndpointTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.MembershipsService.Endpoint

  doctest Ltix.MembershipsService.Endpoint

  describe "new/1" do
    test "rejects a URL that is not an absolute HTTPS URL" do
      for url <- ["http://lms.example.com/memberships", "/memberships", "not a url"] do
        assert {:error,
                %InvalidField{
                  struct: Endpoint,
                  field: :context_memberships_url,
                  value: ^url
                }} =
                 Endpoint.new(url)
      end
    end

    test "rejects a missing URL" do
      for url <- [nil, ""] do
        assert {:error, %InvalidField{field: :context_memberships_url, reason: :required}} =
                 Endpoint.new(url)
      end
    end
  end

  describe "new!/1" do
    test "raises on an invalid URL" do
      assert_raise InvalidField, fn -> Endpoint.new!("http://lms.example.com") end
    end
  end
end
