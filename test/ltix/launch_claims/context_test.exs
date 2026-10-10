defmodule Ltix.LaunchClaims.ContextTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.LaunchClaims.Context

  doctest Ltix.LaunchClaims.Context

  describe "from_json/1" do
    test "returns error for empty map" do
      assert {:error, %MissingClaim{claim: "context.id"}} = Context.from_json(%{})
    end
  end

  describe "to_map/1" do
    test "round-trips through from_json/1" do
      for json <- [
            %{"id" => "ctx-1"},
            %{
              "id" => "ctx-1",
              "label" => "CS101",
              "title" => "Intro",
              "type" => ["CourseSection"]
            }
          ] do
        {:ok, context} = Context.from_json(json)
        assert Context.to_map(context) == json
      end
    end
  end
end
