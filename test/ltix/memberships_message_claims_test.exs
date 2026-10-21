defmodule Ltix.MembershipsMessageClaimsTest do
  use ExUnit.Case, async: true

  import Ltix.Test.MembershipsServiceHelper

  alias Ltix.Claims.Context
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.MembershipsService.Member
  alias Ltix.MembershipsService.MembershipContainer
  alias Ltix.Role

  setup do
    %{client: create_client()}
  end

  @lti "https://purl.imsglobal.org/spec/lti/claim/"

  # Lists and streams a member with `message`, and the `:roles` option's roles.
  defp list_message(client, message, opts \\ []) do
    {roles, opts} = Keyword.pop(opts, :roles, [])
    member = Map.merge(member("user-1"), %{"roles" => roles, "message" => [message]})
    list_and_stream(client, [member], opts)
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
               list_message(client, message)
    end
  end

  test "claims are parsed with the client's plugins, and plugins: replaces them", %{
    client: client
  } do
    message = %{"https://tool.example.com/claim/traced" => "traced"}

    {:ok, plugins} =
      Ltix.PluginSet.resolve([{TestPlugins.Modules, add: [TestPlugins.Traced]}])

    client = %{client | plugins: plugins}

    assert {{:ok, %MembershipContainer{members: [%Member{message: [listed]}]}},
            {:ok, [%Member{message: [streamed]}]}} = list_message(client, message)

    assert present(listed) == %{traced: "traced", roles: []}
    assert present(streamed) == present(listed)

    assert {{:ok, %MembershipContainer{members: [%Member{message: [listed]}]}},
            {:ok, [%Member{message: [streamed]}]}} =
             list_message(client, message, plugins: [])

    assert present(listed) == %{roles: []}
    assert present(streamed) == %{roles: []}
    refute Map.has_key?(listed, :traced)
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
             list_message(client, message, plugins: plugins)

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
             list_message(client, message)

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
                 list_message(client, %{unquote(key) => value})
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
               list_message(client, message, plugins: plugins)

      assert listed.context == nil
      assert listed.traced == nil
      assert present(listed) == expected
      assert present(streamed) == expected
    end
  end

  describe "checks" do
    test "a message with only custom passes, because messages get no validator", %{client: client} do
      message = %{(@lti <> "custom") => %{"country" => "Canada"}}

      assert {{:ok, %MembershipContainer{members: [%Member{message: [listed]}]}},
              {:ok, [%Member{message: [streamed]}]}} = list_message(client, message)

      assert present(listed) == %{custom: %{"country" => "Canada"}, roles: []}
      assert streamed == listed
    end

    test "checks scoped to message types run for the message's type", %{client: client} do
      plugins = [{TestPlugins.Modules, add: [TestPlugins.TitledContext]}]
      context = %{(@lti <> "context") => %{"id" => "course"}}

      assert {{:error, %InvalidClaim{claim: "context", message: "must have a title"}},
              {:error, %InvalidClaim{claim: "context"}}} =
               list_message(
                 client,
                 Map.put(context, @lti <> "message_type", "LtiDeepLinkingRequest"),
                 plugins: plugins
               )

      for message <- [context, Map.put(context, @lti <> "message_type", "LtiResourceLinkRequest")] do
        assert {{:ok, _listed}, {:ok, _streamed}} =
                 list_message(client, message, plugins: plugins)
      end
    end

    test "checks for every message type run for a message without a type", %{client: client} do
      message = %{(@lti <> "context") => %{"id" => "course"}}

      assert {{:error, %InvalidClaim{claim: "context", message: "must have a label"}}, _streamed} =
               list_message(client, message,
                 plugins: [{TestPlugins.Modules, add: [TestPlugins.LabeledContext]}]
               )
    end

    test "role_scope_mentor is checked with the message's roles, or the member's without them", %{
      client: client
    } do
      mentor = %{(@lti <> "role_scope_mentor") => ["user-2"]}
      with_roles = Map.put(mentor, @lti <> "roles", [Role.context_learner()])

      assert {{:ok, _listed}, {:ok, _streamed}} =
               list_message(client, mentor, roles: [Role.context_mentor()])

      for {message, roles} <- [
            {mentor, [Role.context_learner()]},
            {with_roles, [Role.context_mentor()]},
            {Map.put(mentor, @lti <> "roles", []), [Role.context_mentor()]}
          ] do
        assert {{:error,
                 %InvalidClaim{
                   claim: "role_scope_mentor",
                   message: "requires the Mentor role in roles"
                 }}, {:error, %InvalidClaim{claim: "role_scope_mentor"}}} =
                 list_message(client, message, roles: roles)
      end
    end

    test "an override applies in the message types it lists", %{client: client} do
      mentor = %{(@lti <> "role_scope_mentor") => ["user-2"]}
      plugins = [{TestPlugins.Modules, add: [TestPlugins.MentorWithoutRole]}]

      assert {{:ok, _listed}, {:ok, _streamed}} =
               list_message(client, Map.put(mentor, @lti <> "message_type", "LtiTestRequest"),
                 plugins: plugins
               )

      assert {{:error, %InvalidClaim{claim: "role_scope_mentor"}}, _streamed} =
               list_message(
                 client,
                 Map.put(mentor, @lti <> "message_type", "LtiResourceLinkRequest"),
                 plugins: plugins
               )
    end
  end
end
