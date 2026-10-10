defmodule Ltix.GradeService.ResultTest do
  use ExUnit.Case, async: true

  alias Ltix.GradeService.Result

  doctest Result

  describe "from_json/1" do
    test "parses result with all fields" do
      json = %{
        "id" => "https://lms.example.com/context/2923/lineitems/1/results/1",
        "scoreOf" => "https://lms.example.com/context/2923/lineitems/1",
        "userId" => "5323497",
        "resultScore" => 0.83,
        "resultMaximum" => 1,
        "scoringUserId" => "4567890",
        "comment" => "Good work"
      }

      assert {:ok, %Result{} = result} = Result.from_json(json)
      assert result.id == "https://lms.example.com/context/2923/lineitems/1/results/1"
      assert result.score_of == "https://lms.example.com/context/2923/lineitems/1"
      assert result.user_id == "5323497"
      assert result.result_score == 0.83
      assert result.result_maximum == 1
      assert result.scoring_user_id == "4567890"
      assert result.comment == "Good work"
      assert result.extensions == %{}
    end

    test "parses with only userId present" do
      json = %{"userId" => "5323497"}

      assert {:ok, %Result{} = result} = Result.from_json(json)
      assert result.user_id == "5323497"
      assert is_nil(result.id)
      assert is_nil(result.score_of)
      assert is_nil(result.result_score)
      assert is_nil(result.result_maximum)
      assert is_nil(result.scoring_user_id)
      assert is_nil(result.comment)
    end

    test "parses with missing userId (liberal acceptance)" do
      json = %{"resultScore" => 0.5}

      assert {:ok, %Result{user_id: nil, result_score: 0.5}} = Result.from_json(json)
    end
  end

  describe "to_map/1" do
    test "serializes a result built without extensions" do
      result = %Result{user_id: "5", result_score: 0.5, extensions: nil}
      assert Result.to_map(result) == %{"userId" => "5", "resultScore" => 0.5}
    end

    test "round-trips a parsed result with camelCase keys and extensions" do
      json = %{
        "id" => "https://lms.example.com/lineitems/1/results/5",
        "scoreOf" => "https://lms.example.com/lineitems/1",
        "userId" => "5",
        "resultScore" => 0.83,
        "resultMaximum" => 1,
        "scoringUserId" => "instructor-1",
        "comment" => "Nice",
        "https://platform.example.com/extra" => true
      }

      assert {:ok, result} = Result.from_json(json)
      assert Result.to_map(result) == json
    end
  end
end
