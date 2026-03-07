defmodule Ltix.LaunchClaims.ContextTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.Context

  doctest Ltix.LaunchClaims.Context

  describe "from_json/1" do
    # [Core §5.4.1] id is REQUIRED
    test "parses all fields" do
      json = %{
        "id" => "context-001",
        "label" => "CS101",
        "title" => "Intro to Computer Science",
        "type" => [
          "http://purl.imsglobal.org/vocab/lis/v2/course#CourseSection"
        ]
      }

      assert {:ok, %Context{} = ctx} = Context.from_json(json)
      assert ctx.id == "context-001"
      assert ctx.label == "CS101"
      assert ctx.title == "Intro to Computer Science"
      assert ctx.type == ["http://purl.imsglobal.org/vocab/lis/v2/course#CourseSection"]
    end

    test "parses with only required id" do
      assert {:ok, %Context{id: "ctx-1", label: nil, title: nil, type: nil}} =
               Context.from_json(%{"id" => "ctx-1"})
    end

    # [Core §5.4.1] id is REQUIRED
    test "returns error when id missing" do
      assert {:error, error} = Context.from_json(%{"label" => "CS101"})
      assert Exception.message(error) =~ "context.id"
    end

    test "returns error for empty map" do
      assert {:error, _} = Context.from_json(%{})
    end

    # [Core §A.1] context type vocabulary - full URIs
    test "accepts full URI context types" do
      json = %{
        "id" => "ctx-1",
        "type" => [
          "http://purl.imsglobal.org/vocab/lis/v2/course#CourseTemplate",
          "http://purl.imsglobal.org/vocab/lis/v2/course#CourseOffering"
        ]
      }

      assert {:ok, %Context{type: types}} = Context.from_json(json)

      assert types == [
               "http://purl.imsglobal.org/vocab/lis/v2/course#CourseTemplate",
               "http://purl.imsglobal.org/vocab/lis/v2/course#CourseOffering"
             ]
    end

    # [Core §A.1] deprecated simple names MAY be recognized
    test "accepts deprecated simple name context types" do
      json = %{
        "id" => "ctx-1",
        "type" => ["CourseSection"]
      }

      assert {:ok, %Context{type: ["CourseSection"]}} = Context.from_json(json)
    end
  end
end
