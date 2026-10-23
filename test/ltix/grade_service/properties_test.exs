defmodule Ltix.GradeService.PropertiesTest do
  use ExUnit.Case, async: true

  import GradeServiceFixtures

  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Unknown.InvalidPluginSet
  alias Ltix.GradeService
  alias Ltix.GradeService.LineItem
  alias Ltix.GradeService.Result
  alias Ltix.GradeService.Score
  alias Ltix.PluginSet.Conflict
  alias TestPlugins.LaunchUrl
  alias TestPlugins.Modules
  alias TestPlugins.OtherSubmissionType
  alias TestPlugins.ResultFeedback
  alias TestPlugins.ScoreSubmission
  alias TestPlugins.SubmissionType

  @submission_type "https://vendor.example.com/submission_type"
  @launch_url "https://vendor.example.com/launch_url"
  @unrecognized "https://platform.example.com/due_soon"

  defp line_item_json(properties) do
    Map.merge(%{"id" => line_item_url(), "label" => "Essay", "scoreMaximum" => 10}, properties)
  end

  describe "line item properties" do
    test "a create-only property is sent on create and left out of an update after a GET" do
      client = create_client(plugins: [{Modules, add: [SubmissionType]}])
      read = line_item_json(%{@submission_type => %{"type" => "external_tool"}})

      stub_requests(fn
        "POST", body -> Map.put(body, "id", line_item_url())
        "GET", nil -> read
        "PUT", body -> body
      end)

      assert {:ok, created} =
               GradeService.create_line_item(client,
                 label: "Essay",
                 score_maximum: 10,
                 submission_type: %{type: "external_tool"}
               )

      assert_received {"POST", %{@submission_type => %{"type" => "external_tool"}}}
      assert created.extensions.submission_type == %{type: "external_tool"}

      assert {:ok, fetched} = GradeService.get_line_item(client)
      assert fetched.extensions.submission_type == %{type: "external_tool"}
      assert fetched.unrecognized == %{}

      assert {:ok, _updated} =
               GradeService.update_line_item(client, %{fetched | label: "Final essay"})

      assert_received {"PUT", sent}
      assert sent == %{"id" => line_item_url(), "label" => "Final essay", "scoreMaximum" => 10}
    end

    test "an anonymous property a plugin adds with add_property/2 is parsed with its schema and sent" do
      build =
        &LineItem.add_property(&1,
          property: "https://vendor.example.com/due_rule",
          name: :due_rule,
          schema: Zoi.string()
        )

      client = create_client(plugins: [{Modules, build: build}])

      stub_requests(fn
        "POST", body -> Map.put(body, "id", line_item_url())
        "GET", nil -> line_item_json(%{"https://vendor.example.com/due_rule" => "weekly"})
      end)

      assert {:ok, _created} =
               GradeService.create_line_item(client,
                 label: "Essay",
                 score_maximum: 10,
                 due_rule: "daily"
               )

      assert_received {"POST", %{"https://vendor.example.com/due_rule" => "daily"}}

      assert {:ok, fetched} = GradeService.get_line_item(client)
      assert fetched.extensions.due_rule == "weekly"

      stub_requests(fn "GET", nil ->
        line_item_json(%{"https://vendor.example.com/due_rule" => 7})
      end)

      assert {:error, %InvalidClaim{value: 7}} = GradeService.get_line_item(client)
    end

    test "scores and results take anonymous properties" do
      build = fn plugin ->
        plugin
        |> Score.add_property(property: "https://vendor.example.com/attempt", name: :attempt)
        |> Result.add_property(property: "https://vendor.example.com/grader", name: :grader)
      end

      plugins = [{Modules, build: build}]

      assert {:ok, score} =
               Score.new(
                 user_id: "u1",
                 activity_progress: :completed,
                 grading_progress: :fully_graded,
                 attempt: 2,
                 plugins: plugins
               )

      assert score.extensions.attempt == 2

      assert {:ok, result} =
               Ltix.Type.from_json(
                 Result,
                 %{
                   "id" => "result-1",
                   "userId" => "u1",
                   "https://vendor.example.com/grader" => "ada"
                 },
                 plugins: plugins
               )

      assert result.extensions.grader == "ada"
    end

    test "a property that two plugins add with the same options is sent and parsed once" do
      plugins =
        for name <- ["First", "Second"],
            do: {Modules, name: name, add: [{TestPlugins.Tagged, tag: "shared"}]}

      client = create_client(plugins: plugins)

      stub_requests(fn "POST", body -> Map.put(body, "id", line_item_url()) end)

      assert {:ok, created} =
               GradeService.create_line_item(client,
                 label: "Essay",
                 score_maximum: 10,
                 tagged: "x"
               )

      assert_received {"POST", %{"https://vendor.example.com/tagged" => "shared:x"}}
      assert created.extensions.tagged == "x"
    end

    test "a read-only property is parsed on a GET and never sent" do
      client = create_client(plugins: [{Modules, add: [LaunchUrl]}])

      stub_requests(fn
        "GET", nil -> line_item_json(%{@launch_url => "https://tool.example.com/essay"})
        _method, body -> Map.put(body, "id", line_item_url())
      end)

      assert {:ok, fetched} = GradeService.get_line_item(client)
      assert fetched.extensions.launch_url == URI.parse("https://tool.example.com/essay")

      assert {:ok, _updated} = GradeService.update_line_item(client, fetched)
      assert_received {"PUT", sent}
      refute Map.has_key?(sent, @launch_url)

      assert {:ok, _created} = GradeService.create_line_item(client, %{fetched | id: nil})
      assert_received {"POST", sent}
      refute Map.has_key?(sent, @launch_url)
    end

    test "an undeclared property read on a GET is sent back unchanged on a PUT" do
      client = create_client(plugins: [])

      read =
        line_item_json(%{
          @unrecognized => %{"days" => [1, 2]},
          @submission_type => %{"type" => "none"}
        })

      stub_requests(fn
        "GET", nil -> read
        "PUT", body -> body
      end)

      assert {:ok, fetched} = GradeService.get_line_item(client)
      assert fetched.extensions == %{}

      assert fetched.unrecognized == %{
               @unrecognized => %{"days" => [1, 2]},
               @submission_type => %{"type" => "none"}
             }

      assert {:ok, _updated} = GradeService.update_line_item(client, fetched)
      assert_received {"PUT", ^read}
    end

    test "standard fields replace unrecognized properties of the same name" do
      stub_requests(fn "PUT", body -> body end)

      item = %LineItem{
        id: line_item_url(),
        label: "Essay",
        score_maximum: 10,
        unrecognized: %{"label" => "Old"}
      }

      assert {:ok, _updated} = GradeService.update_line_item(create_client(plugins: []), item)
      assert_received {"PUT", %{"label" => "Essay"}}
    end

    test "every line item in a list is parsed with the plugin set" do
      client = create_client(plugins: [{Modules, add: [SubmissionType]}])

      stub_requests(fn "GET", nil ->
        [
          line_item_json(%{@submission_type => %{"type" => "none"}}),
          line_item_json(%{"id" => line_items_url() <> "/2/lineitem"})
        ]
      end)

      assert {:ok, [first, second]} = GradeService.list_line_items(client)
      assert first.extensions == %{submission_type: %{type: "none"}}
      assert second.extensions == %{}

      assert {:ok, stream} = GradeService.stream_line_items(client)
      assert [streamed, _second] = Enum.to_list(stream)
      assert streamed.extensions == %{submission_type: %{type: "none"}}
    end

    test "create_line_item/3 sends a property set in a line item's extensions" do
      client = create_client(plugins: [{Modules, add: [SubmissionType]}])
      stub_requests(fn "POST", body -> Map.put(body, "id", line_item_url()) end)

      item = %LineItem{
        label: "Essay",
        score_maximum: 10,
        extensions: %{submission_type: %{type: "none"}}
      }

      assert {:ok, %LineItem{extensions: %{submission_type: %{type: "none"}}}} =
               GradeService.create_line_item(client, item)

      assert_received {"POST", %{@submission_type => %{"type" => "none"}}}
    end

    test "create_line_item/3 raises for an option that is neither a field nor a property name" do
      client = create_client(plugins: [{Modules, add: [SubmissionType]}])

      assert_raise InvalidOption, "Option :submision_type is unknown", fn ->
        GradeService.create_line_item(client,
          label: "Essay",
          score_maximum: 10,
          submision_type: %{type: "none"}
        )
      end

      assert_raise InvalidOption, "Option :submission_type is unknown", fn ->
        GradeService.create_line_item(client,
          label: "Essay",
          score_maximum: 10,
          submission_type: %{type: "none"},
          plugins: []
        )
      end
    end

    test "a property value that fails to parse fails the call" do
      client = create_client(plugins: [{Modules, add: [SubmissionType]}])
      stub_requests(fn "GET", nil -> line_item_json(%{@submission_type => "external_tool"}) end)

      assert {:error,
              %InvalidClaim{
                claim: "line_item.https://vendor.example.com/submission_type",
                value: "external_tool",
                message: "must be an object with a type"
              }} = GradeService.get_line_item(client)
    end
  end

  describe "score and result properties" do
    test "post_score/3 sends a score property with the options it was added with" do
      plugins = [{Modules, add: [{ScoreSubmission, submission_type: "online_url"}]}]
      client = create_client(plugins: plugins)
      stub_requests(fn "POST", _body -> nil end)

      assert {:ok, score} =
               Score.new(
                 user_id: "u1",
                 activity_progress: :completed,
                 grading_progress: :fully_graded,
                 vendor_submission: "https://example.com/work",
                 plugins: plugins
               )

      assert score.extensions == %{vendor_submission: "https://example.com/work"}
      assert :ok = GradeService.post_score(client, score)

      assert_received {"POST",
                       %{
                         "userId" => "u1",
                         "https://vendor.example.com/submission" => %{
                           "submission_data" => "https://example.com/work",
                           "submission_type" => "online_url"
                         }
                       }}
    end

    test "Score.new/1 returns an error for a field that is neither standard nor a property name" do
      assert {:error, %InvalidField{struct: Score, field: :vendor_submision, reason: :unknown}} =
               Score.new(
                 user_id: "u1",
                 activity_progress: :completed,
                 grading_progress: :fully_graded,
                 vendor_submision: "https://example.com/work",
                 plugins: [{Modules, add: [ScoreSubmission]}]
               )
    end

    test "list_results/2 and stream_results/2 parse a result property" do
      client = create_client(plugins: [{Modules, add: [ResultFeedback]}])

      stub_requests(fn "GET", nil ->
        [
          %{
            "userId" => "u1",
            "resultScore" => 0.5,
            "https://vendor.example.com/feedback" => %{"text" => "Good"}
          }
        ]
      end)

      assert {:ok, [%Result{user_id: "u1"} = listed]} = GradeService.list_results(client)
      assert listed.extensions.feedback == %{text: "Good"}

      assert {:ok, stream} = GradeService.stream_results(client)
      assert [streamed] = Enum.to_list(stream)
      assert streamed.extensions.feedback == %{text: "Good"}
    end
  end

  # The conflict, with each party replaced by its entry's module.
  defp modules(%Conflict{parties: parties} = conflict),
    do: %{conflict | parties: Enum.map(parties, & &1.module)}

  describe "plugin sets" do
    test "a client authenticated from a launch parses the properties of the launch's plugins" do
      launch =
        Ltix.Test.build_launch(Ltix.Test.setup_platform!(),
          ags_endpoint: endpoint(),
          plugins: [{Modules, add: [LaunchUrl]}]
        )

      Ltix.Test.stub_token_response(scopes: scopes())

      stub_requests(fn "GET", nil ->
        line_item_json(%{@launch_url => "https://tool.example.com/essay"})
      end)

      assert {:ok, client} =
               GradeService.authenticate(launch, req_options: [plug: {Req.Test, GradeService}])

      assert {:ok, fetched} = GradeService.get_line_item(client)
      assert fetched.extensions.launch_url == URI.parse("https://tool.example.com/essay")
    end

    test "plugins: replaces the client's plugin set" do
      client = create_client(plugins: [{Modules, add: [LaunchUrl]}])

      stub_requests(fn "GET", nil ->
        line_item_json(%{@launch_url => "https://tool.example.com/essay"})
      end)

      assert {:ok, fetched} = GradeService.get_line_item(client, plugins: [])
      assert fetched.unrecognized == %{@launch_url => "https://tool.example.com/essay"}
    end

    test "two modules declaring one score or result property are a conflict" do
      client = create_client(plugins: [])
      score = Score.new!(user_id: "u", activity_progress: :completed, grading_progress: :pending)

      for {call, parties, type, property} <- [
            {&GradeService.post_score(client, score, plugins: &1),
             [ScoreSubmission, TestPlugins.OtherSubmission], Score, "submission"},
            {&GradeService.list_results(client, plugins: &1),
             [ResultFeedback, TestPlugins.OtherFeedback], Result, "feedback"}
          ] do
        assert {:error, %InvalidPluginSet{conflicts: [conflict]}} =
                 call.([{Modules, add: parties}])

        assert modules(conflict) == %Conflict{
                 parties: parties,
                 reason:
                   ~s(both declare the property "https://vendor.example.com/#{property}" on #{inspect(type)})
               }
      end
    end

    test "a score property that two plugins add with different options is a conflict" do
      client = create_client(plugins: [])
      score = Score.new!(user_id: "u", activity_progress: :completed, grading_progress: :pending)

      plugins =
        for type <- ["essay", "quiz"],
            do: {Modules, name: type, add: [{ScoreSubmission, submission_type: type}]}

      assert {:error, %InvalidPluginSet{conflicts: [conflict]}} =
               GradeService.post_score(client, score, plugins: plugins)

      assert modules(conflict) == %Conflict{
               parties: [ScoreSubmission, ScoreSubmission],
               reason:
                 ~s(both declare the property "https://vendor.example.com/submission" on Ltix.GradeService.Score)
             }
    end

    test "two modules declaring one line item property are a conflict" do
      client = create_client(plugins: [])

      assert {:error, %InvalidPluginSet{conflicts: [conflict]}} =
               GradeService.get_line_item(client,
                 plugins: [
                   {Modules, name: "Submissions", add: [SubmissionType, OtherSubmissionType]}
                 ]
               )

      assert modules(conflict) == %Conflict{
               parties: [SubmissionType, OtherSubmissionType],
               reason:
                 ~s(both declare the property "#{@submission_type}" on Ltix.GradeService.LineItem)
             }
    end

    test "two modules declaring one line item property name are a conflict" do
      client = create_client(plugins: [])

      assert {:error, %InvalidPluginSet{conflicts: [conflict]}} =
               GradeService.get_line_item(client,
                 plugins: [{Modules, add: [SubmissionType, TestPlugins.SubmissionKind]}]
               )

      assert modules(conflict) == %Conflict{
               parties: [SubmissionType, TestPlugins.SubmissionKind],
               reason: "both declare the name :submission_type on Ltix.GradeService.LineItem"
             }
    end

    test "a property declaring a standard field's name is a conflict" do
      client = create_client(plugins: [])

      assert {:error, %InvalidPluginSet{conflicts: [conflict]}} =
               GradeService.get_line_item(client,
                 plugins: [{Modules, add: [TestPlugins.LabelName]}]
               )

      assert modules(conflict) == %Conflict{
               parties: [TestPlugins.LabelName],
               reason:
                 "declares the name :label, which is a standard field of Ltix.GradeService.LineItem"
             }
    end

    test "Score.new/1 returns a conflict for a property declaring a name Ltix reserves" do
      assert {:error, %InvalidPluginSet{conflicts: [conflict]}} =
               Score.new(
                 user_id: "u1",
                 activity_progress: :completed,
                 grading_progress: :fully_graded,
                 vendor_submission: "https://example.com/work",
                 plugins: [{Modules, add: [ScoreSubmission, TestPlugins.PluginsName]}]
               )

      assert modules(conflict) == %Conflict{
               parties: [TestPlugins.PluginsName],
               reason: "declares the name :plugins, which Ltix reserves"
             }
    end

    test "a property without a name raises when it compiles" do
      assert_raise ArgumentError,
                   "Ltix.GradeService.PropertiesTest.Unnamed requires the :property and :name options on its first `use` of a type",
                   fn ->
                     defmodule Unnamed do
                       use Ltix.GradeService.LineItem
                     end
                   end
    end

    test "a property declaring a standard field's JSON name is a conflict" do
      client = create_client(plugins: [])

      assert {:error, %InvalidPluginSet{conflicts: [conflict]}} =
               GradeService.get_line_item(client,
                 plugins: [{Modules, add: [TestPlugins.LabelProperty]}]
               )

      assert modules(conflict) == %Conflict{
               parties: [TestPlugins.LabelProperty],
               reason:
                 ~s(declares the property "label", which is a standard field of Ltix.GradeService.LineItem)
             }
    end
  end
end
