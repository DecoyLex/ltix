defmodule Ltix.LaunchClaims.LisTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.Lis

  doctest Ltix.LaunchClaims.Lis

  describe "from_json/1" do
    # [Core §5.4.5] All fields optional
    test "parses all fields" do
      json = %{
        "person_sourcedid" => "sis-person-001",
        "course_offering_sourcedid" => "sis-course-001",
        "course_section_sourcedid" => "sis-section-001"
      }

      assert {:ok, %Lis{} = lis} = Lis.from_json(json)
      assert lis.person_sourcedid == "sis-person-001"
      assert lis.course_offering_sourcedid == "sis-course-001"
      assert lis.course_section_sourcedid == "sis-section-001"
    end

    test "parses empty map" do
      assert {:ok,
              %Lis{
                person_sourcedid: nil,
                course_offering_sourcedid: nil,
                course_section_sourcedid: nil
              }} = Lis.from_json(%{})
    end

    test "parses partial fields" do
      assert {:ok, %Lis{person_sourcedid: "person-1", course_offering_sourcedid: nil}} =
               Lis.from_json(%{"person_sourcedid" => "person-1"})
    end
  end
end
