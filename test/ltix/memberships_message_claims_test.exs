defmodule Ltix.MembershipsMessageClaimsTest do
  use ExUnit.Case, async: true

  import Ltix.Test.MembershipsServiceHelper

  alias Ltix.Claims.Context
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.MembershipsService
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer

  setup do
    %{client: create_client()}
  end

  defp list_and_stream(client, message, opts \\ []) do
    body = Map.put(container(1), "members", [Map.put(member("user-1"), "message", [message])])
    stub_pages(1, body)

    listed = MembershipsService.list_members(client, opts)

    streamed =
      with {:ok, stream} <- MembershipsService.stream_members(client, opts) do
        try do
          {:ok, Enum.to_list(stream)}
        rescue
          error in InvalidClaim -> {:error, error}
        end
      end

    {listed, streamed}
  end

  # The claims of a message that aren't nil.
  defp present(claims), do: Map.reject(claims, fn {_claim, value} -> value == nil end)

  test "malformed claims fail the call", %{client: client} do
    for {message, claim, value} <- [
          {%{"https://purl.imsglobal.org/spec/lti/claim/message_type" => 123}, "message_type",
           123},
          {%{"aud" => [123]}, "aud.0", 123},
          {%{"exp" => "invalid"}, "exp", "invalid"},
          {%{"https://purl.imsglobal.org/spec/lti/claim/resource_link" => []}, "resource_link",
           []},
          {%{"https://purl.imsglobal.org/spec/lti-dl/claim/deep_linking_settings" => 123},
           "deep_linking_settings", 123}
        ] do
      assert {{:error, %InvalidClaim{claim: ^claim, value: ^value}},
              {:error, %InvalidClaim{claim: ^claim, value: ^value}}} =
               list_and_stream(client, message)
    end
  end

  test "claims are parsed with the call's plugins", %{client: client} do
    message = %{
      "exp" => 123.5,
      "iat" => 122.5,
      "https://purl.imsglobal.org/spec/lti/claim/context" => %{"id" => "course"},
      "https://purl.imsglobal.org/spec/lti/claim/roles" => ["Instructor"],
      "https://purl.imsglobal.org/spec/lti/claim/custom" => %{"country" => "Canada"},
      "https://tool.example.com/claim/traced" => %{"value" => 123},
      "https://vendor.example.com/unknown" => [123]
    }

    plugins = [{TestPlugins.Modules, add: [TestPlugins.Traced]}]

    assert {{:ok, %MembershipContainer{members: [%Member{message: [listed]}]}},
            {:ok, [%Member{message: [streamed]}]}} =
             list_and_stream(client, message, plugins: plugins)

    for claims <- [listed, streamed] do
      assert present(claims) == %{
               expires_at: 123.5,
               issued_at: 122.5,
               context: %Context{id: "course"},
               roles: ["Instructor"],
               custom: %{"country" => "Canada"},
               traced: %{"value" => 123}
             }
    end

    assert {{:ok, %MembershipContainer{members: [%Member{message: [claims]}]}}, _streamed} =
             list_and_stream(client, message)

    refute Map.has_key?(claims, :traced)
  end

  for {key, claim, invalid_values} <- [
        {"aud", "aud", [{123, ""}, {[123], ".0"}]},
        {"exp", "exp", [{"123", ""}]},
        {"nonce", "nonce", [{123, ""}]},
        {"azp", "azp", [{123, ""}]},
        {"https://purl.imsglobal.org/spec/lti/claim/version", "version", [{123, ""}]}
      ] do
    test "a malformed #{claim} fails the call", %{client: client} do
      for {value, suffix} <- unquote(Macro.escape(invalid_values)) do
        expected_claim = unquote(claim) <> suffix

        assert {{:error, %InvalidClaim{claim: ^expected_claim}},
                {:error, %InvalidClaim{claim: ^expected_claim}}} =
                 list_and_stream(client, %{unquote(key) => value})
      end
    end
  end

  test "absent and null claims are nil, and absent roles are empty", %{client: client} do
    plugins = [{TestPlugins.Modules, add: [TestPlugins.Traced]}]

    nulls =
      Map.new(
        ~w(iss sub aud exp iat nonce azp email name given_name family_name middle_name picture locale) ++
          Enum.map(
            ~w(message_type version deployment_id target_link_uri role_scope_mentor),
            &("https://purl.imsglobal.org/spec/lti/claim/" <> &1)
          ),
        &{&1, nil}
      )

    for {message, expected} <- [
          {%{}, %{roles: []}},
          {nulls, %{roles: []}},
          {%{"aud" => "tool", "exp" => 123.5, "iat" => 122.5},
           %{audience: "tool", expires_at: 123.5, issued_at: 122.5, roles: []}},
          {%{
             "aud" => ["tool", "other"],
             "exp" => 123,
             "iat" => 122,
             "https://purl.imsglobal.org/spec/lti/claim/role_scope_mentor" => []
           },
           %{
             audience: ["tool", "other"],
             expires_at: 123,
             issued_at: 122,
             role_scope_mentor: [],
             roles: []
           }}
        ] do
      assert {{:ok, %MembershipContainer{members: [%Member{message: [listed]}]}},
              {:ok, [%Member{message: [streamed]}]}} =
               list_and_stream(client, message, plugins: plugins)

      assert listed.context == nil
      assert listed.traced == nil
      assert present(listed) == expected
      assert present(streamed) == expected
    end
  end
end
