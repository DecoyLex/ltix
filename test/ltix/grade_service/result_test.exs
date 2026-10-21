defmodule Ltix.GradeService.ResultTest do
  use ExUnit.Case, async: true

  import Ltix.Test.GradeServiceHelper

  alias Ltix.GradeService
  alias Ltix.GradeService.Result

  doctest Result

  # Returns the results `list_results/2` parses from `json`.
  defp read(json) do
    stub_requests(fn "GET", nil -> json end)
    {:ok, results} = GradeService.list_results(create_client())
    results
  end

  test "parses every field" do
    json = %{
      "id" => "https://lms.example.com/context/2923/lineitems/1/results/1",
      "scoreOf" => "https://lms.example.com/context/2923/lineitems/1",
      "userId" => "5323497",
      "resultScore" => 0.83,
      "resultMaximum" => 1,
      "scoringUserId" => "4567890",
      "comment" => "Good work"
    }

    assert read([json]) == [
             %Result{
               id: "https://lms.example.com/context/2923/lineitems/1/results/1",
               score_of: "https://lms.example.com/context/2923/lineitems/1",
               user_id: "5323497",
               result_score: 0.83,
               result_maximum: 1,
               scoring_user_id: "4567890",
               comment: "Good work"
             }
           ]
  end

  test "leaves missing fields nil, including userId" do
    assert read([%{"userId" => "5323497"}, %{"resultScore" => 0.5}]) == [
             %Result{user_id: "5323497"},
             %Result{result_score: 0.5}
           ]
  end

  test "keeps properties no plugin declares" do
    assert [%Result{unrecognized: %{"https://platform.example.com/extra" => true}}] =
             read([%{"userId" => "5", "https://platform.example.com/extra" => true}])
  end
end
