defmodule Ltix.LaunchClaims.ClaimHelpersTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.LaunchClaims.ClaimHelpers

  defmodule TestClaim do
    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(coerce: true),
                type: Zoi.list(Zoi.string(coerce: true)) |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
  end

  describe "from_json/4" do
    test "returns {:ok, struct} on valid input" do
      json = %{"id" => "abc", "type" => ["foo"]}

      assert {:ok, %TestClaim{id: "abc", type: ["foo"]}} =
               ClaimHelpers.from_json(TestClaim.schema(), json, "test", "Spec §1")
    end

    test "missing required field produces MissingClaim" do
      assert {:error, %Invalid{errors: [%MissingClaim{claim: "test.id"}]}} =
               ClaimHelpers.from_json(TestClaim.schema(), %{}, "test", "Spec §1")
    end

    test "invalid type produces InvalidClaim with the bad value" do
      json = %{"id" => "ok", "type" => "not_a_list"}

      assert {:error, %Invalid{errors: [%InvalidClaim{} = err]}} =
               ClaimHelpers.from_json(TestClaim.schema(), json, "test", "Spec §1")

      assert err.claim == "test.type"
      assert err.value == "not_a_list"
      assert err.spec_ref == "Spec §1"
    end

    test "accumulates multiple errors" do
      json = %{"type" => "not_a_list"}

      assert {:error, %Invalid{errors: errors}} =
               ClaimHelpers.from_json(TestClaim.schema(), json, "test", "Spec §1")

      assert length(errors) == 2

      assert Enum.any?(errors, &match?(%MissingClaim{claim: "test.id"}, &1))
      assert Enum.any?(errors, &match?(%InvalidClaim{claim: "test.type"}, &1))
    end
  end
end
