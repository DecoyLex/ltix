defmodule Ltix.JWT.KeySetNotStartedTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Unknown.KeySetNotStarted
  alias Ltix.JWT.KeySet

  test "a lookup raises with the child to add for a named key set cache" do
    registration =
      Ltix.Registration.new!(
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/jwks"
      )

    error =
      assert_raise KeySetNotStarted,
                   "Key set cache MyApp.LtiKeys is not started. " <>
                     "Add {Ltix.JWT.KeySet, name: MyApp.LtiKeys} to your application's supervision tree.",
                   fn -> KeySet.get_key(registration, "kid", key_set: MyApp.LtiKeys) end

    assert Ltix.Errors.status_code(error) == 500
  end

  test "the default key set cache's message has the child without options" do
    assert Exception.message(KeySetNotStarted.exception(key_set: KeySet)) ==
             "Key set cache Ltix.JWT.KeySet is not started. " <>
               "Add Ltix.JWT.KeySet to your application's supervision tree."
  end
end
