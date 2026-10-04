defmodule Ltix.LaunchClaims.LISTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.LIS

  doctest Ltix.LaunchClaims.LIS

  describe "from_json/1" do
    # [Core §5.4.5] All fields optional
    test "parses all fields" do
      json = %{
        "person_sourcedid" => "sis-person-001",
        "course_offering_sourcedid" => "sis-course-001",
        "course_section_sourcedid" => "sis-section-001"
      }

      assert {:ok, %LIS{} = lis} = LIS.from_json(json)
      assert lis.person_sourcedid == "sis-person-001"
      assert lis.course_offering_sourcedid == "sis-course-001"
      assert lis.course_section_sourcedid == "sis-section-001"
    end
  end
end
