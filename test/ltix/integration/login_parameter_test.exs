defmodule Ltix.Integration.LoginParameterTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.MissingParameter
  alias Ltix.Test.StorageAdapter

  @launch_url "https://tool.example.com/launch"

  setup do
    platform = Ltix.Test.setup_platform!()

    other_registration = %{
      platform.registration
      | client_id: "other-client",
        auth_endpoint: "https://platform.example.com/other-authorize"
    }

    pid =
      start_supervised!(
        {StorageAdapter, platforms: [platform], registrations: [other_registration]}
      )

    StorageAdapter.set_pid(pid)
    %{platform: platform, other_registration: other_registration}
  end

  for parameter <- ~w(iss client_id) do
    test "rejects nonstring #{parameter}", context do
      parameter = unquote(parameter)

      for value <- [%{"hostile" => "value"}, [], ["value"], 123, true, false, nil] do
        params = Map.put(Ltix.Test.login_params(context.platform), parameter, value)

        assert {:error, %MissingParameter{parameter: ^parameter, class: :invalid}} =
                 Ltix.handle_login(params, @launch_url, storage_adapter: StorageAdapter)
      end
    end
  end

  test "retains missing parameter errors for absent, null, and empty required fields", context do
    for parameter <- ~w(iss login_hint target_link_uri), value <- [nil, "", :absent] do
      params = Ltix.Test.login_params(context.platform)

      params =
        if value == :absent,
          do: Map.delete(params, parameter),
          else: Map.put(params, parameter, value)

      assert {:error, %MissingParameter{parameter: ^parameter, class: :invalid}} =
               Ltix.handle_login(params, @launch_url, storage_adapter: StorageAdapter)
    end
  end

  test "accepts absent optional parameters and selects a registration by issuer", context do
    assert {:ok, login} =
             Ltix.handle_login(Ltix.Test.login_params(context.platform), @launch_url,
               storage_adapter: StorageAdapter
             )

    query = URI.decode_query(URI.parse(login.redirect_uri).query)
    assert query["client_id"] == context.platform.registration.client_id
    refute Map.has_key?(query, "lti_message_hint")
  end

  test "selects the requested client and preserves opaque hints exactly", context do
    login_hint = "  user+hint/%?&=é  "

    for message_hint <- ["  message+hint/%?&=é  ", ""] do
      params =
        context.platform
        |> Ltix.Test.login_params(login_hint: login_hint)
        |> Map.put("client_id", context.other_registration.client_id)
        |> Map.put("lti_message_hint", message_hint)
        |> Map.put("unknown_extension", %{"ignored" => true})

      assert {:ok, login} =
               Ltix.handle_login(params, @launch_url, storage_adapter: StorageAdapter)

      uri = URI.parse(login.redirect_uri)
      query = URI.decode_query(uri.query)
      assert uri.path == "/other-authorize"
      assert query["client_id"] == context.other_registration.client_id
      assert query["login_hint"] == login_hint
      assert query["lti_message_hint"] == message_hint
      assert query["redirect_uri"] == @launch_url
    end
  end
end
