defmodule Ltix.DeepLinkingTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking
  alias Ltix.DeepLinking.ContentItem.File
  alias Ltix.DeepLinking.ContentItem.HTMLFragment
  alias Ltix.DeepLinking.ContentItem.Image
  alias Ltix.DeepLinking.ContentItem.Link
  alias Ltix.DeepLinking.ContentItem.LTIResourceLink
  alias Ltix.DeepLinking.LineItem
  alias Ltix.DeepLinking.Response
  alias Ltix.Errors.Invalid.ContentItemsExceedLimit
  alias Ltix.Errors.Invalid.ContentItemTypeNotAccepted
  alias Ltix.Errors.Invalid.InvalidContentItem
  alias Ltix.Errors.Invalid.InvalidMessageType
  alias Ltix.Errors.Invalid.InvalidOption
  alias Ltix.Errors.Invalid.LineItemNotAccepted
  alias Ltix.Errors.Invalid.MediaTypeNotAccepted
  alias Ltix.Errors.Invalid.PresentationTargetNotAccepted
  alias Ltix.Errors.Unknown.InvalidPluginSet
  alias Ltix.GradeService
  alias Ltix.PluginSet.Conflict
  alias Ltix.PluginSet.Entry
  alias Ltix.Test.StorageAdapter
  alias TestPlugins.Modules

  alias TestPlugins.ItemCount
  alias TestPlugins.OtherPoll
  alias TestPlugins.OtherReview
  alias TestPlugins.OtherWeight
  alias TestPlugins.Poll
  alias TestPlugins.RejectResponse
  alias TestPlugins.Rubric
  alias TestPlugins.SubmissionReview
  alias TestPlugins.Weight

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @dl "https://purl.imsglobal.org/spec/lti-dl/claim/"

  # Forwards events emitted by the test process, ignoring concurrent tests.
  def forward_own_event(event, _measurements, metadata, {test_pid, ref}) do
    if self() == test_pid, do: send(test_pid, {ref, List.last(event), metadata})
  end

  # Builds a response and returns the content items in its JWT.
  defp content_items(platform, launch, items, opts \\ []) do
    {:ok, response} = DeepLinking.build_response(launch, items, opts)
    {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, response.jwt)
    claims[@dl <> "content_items"]
  end

  setup do
    %{platform: Ltix.Test.setup_platform!()}
  end

  describe "build_response/3 message type validation" do
    test "returns InvalidMessageType for a resource link launch", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform)

      assert {:error, %InvalidMessageType{message_type: "LtiResourceLinkRequest"}} =
               DeepLinking.build_response(launch)
    end

    test "returns InvalidMessageType for a launch without a message type", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      launch = %{launch | claims: Map.delete(launch.claims, :message_type)}

      assert {:error, %InvalidMessageType{message_type: nil}} =
               DeepLinking.build_response(launch)
    end
  end

  describe "build_response/3 for a launch without a deployment" do
    test "leaves out the deployment ID", %{platform: platform} do
      StorageAdapter.set_pid(start_supervised!({StorageAdapter, platforms: [platform]}))

      {:ok, launch} =
        LaunchFlow.launch(
          platform,
          [message_type: :deep_linking, claims: %{(@lti <> "deployment_id") => nil}],
          plugins: [{Modules, add: [TestPlugins.WithoutDeploymentId]}]
        )

      {:ok, response} = DeepLinking.build_response(launch)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, response.jwt)

      refute Map.has_key?(claims, @lti <> "deployment_id")
      assert claims[@lti <> "message_type"] == "LtiDeepLinkingResponse"
    end
  end

  describe "build_response/3 success" do
    test "JWT is verifiable with tool's public key", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(launch)

      assert {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, jwt)
      assert claims["iss"] == platform.registration.client_id
      assert claims["aud"] == platform.registration.issuer
      assert claims["azp"] == platform.registration.issuer
    end

    test "JWT contains required LTI claims", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(launch)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, jwt)

      assert claims[@lti <> "message_type"] == "LtiDeepLinkingResponse"
      assert claims[@lti <> "version"] == "1.3.0"
      assert claims[@lti <> "deployment_id"] == platform.deployment.deployment_id
    end

    test "JWT has correct exp/iat/nonce", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(launch)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, jwt)

      now = System.system_time(:second)
      assert claims["iat"] >= now - 1
      assert claims["exp"] - claims["iat"] == 300
      assert claims["nonce"] =~ ~r/\A[A-Za-z0-9_-]{22}\z/
    end

    test "JWT header has kid and RS256 alg", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(launch)

      %JOSE.JWS{alg: {_mod, alg}, fields: header} = JOSE.JWT.peek_protected(jwt)
      assert header["kid"] == platform.tool_jwk.kid
      assert alg == :RS256
    end
  end

  describe "build_response/3 content items" do
    test "serializes each of Deep Linking's content item types", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      icon = [url: "https://example.com/icon.png", width: 16, height: 16]
      thumbnail = [url: "https://example.com/thumb.png"]

      items = [
        Link.new!(
          url: "https://example.com",
          title: "Docs",
          text: "Read the docs",
          icon: icon,
          thumbnail: thumbnail,
          embed: [html: "<p>Hi</p>"],
          window: [target_name: "docs", width: 800, height: 600, window_features: "menubar=no"],
          iframe: [src: "https://example.com/embed", width: 640, height: 480]
        ),
        LTIResourceLink.new!(
          url: "https://tool.example.com/quizzes/7",
          title: "Quiz",
          text: "Take the quiz",
          icon: icon,
          thumbnail: thumbnail,
          window: [target_name: "quiz"],
          iframe: [width: 640, height: 480],
          custom: [quiz_id: "7"],
          line_item: [
            score_maximum: 100,
            label: "Quiz",
            resource_id: "quiz-7",
            tag: "grade",
            grades_released: true
          ],
          available: [
            start_date_time: ~U[2026-01-01 00:00:00Z],
            end_date_time: ~U[2026-06-30 23:59:59Z]
          ],
          submission: [end_date_time: ~U[2026-06-15 23:59:59Z]]
        ),
        File.new!(
          url: "https://example.com/syllabus.pdf",
          title: "Syllabus",
          text: "The course syllabus",
          icon: icon,
          thumbnail: thumbnail,
          media_type: "application/pdf",
          expires_at: ~U[2026-12-31 23:59:59Z]
        ),
        HTMLFragment.new!(html: "<p>Hello</p>", title: "Greeting", text: "A greeting"),
        Image.new!(
          url: "https://example.com/diagram.png",
          title: "Diagram",
          text: "A diagram",
          icon: icon,
          thumbnail: thumbnail,
          width: 800,
          height: 600
        )
      ]

      icon_json = %{"url" => "https://example.com/icon.png", "width" => 16, "height" => 16}
      thumbnail_json = %{"url" => "https://example.com/thumb.png"}

      assert content_items(platform, launch, items) == [
               %{
                 "type" => "link",
                 "url" => "https://example.com",
                 "title" => "Docs",
                 "text" => "Read the docs",
                 "icon" => icon_json,
                 "thumbnail" => thumbnail_json,
                 "embed" => %{"html" => "<p>Hi</p>"},
                 "window" => %{
                   "targetName" => "docs",
                   "width" => 800,
                   "height" => 600,
                   "windowFeatures" => "menubar=no"
                 },
                 "iframe" => %{
                   "src" => "https://example.com/embed",
                   "width" => 640,
                   "height" => 480
                 }
               },
               %{
                 "type" => "ltiResourceLink",
                 "url" => "https://tool.example.com/quizzes/7",
                 "title" => "Quiz",
                 "text" => "Take the quiz",
                 "icon" => icon_json,
                 "thumbnail" => thumbnail_json,
                 "window" => %{"targetName" => "quiz"},
                 "iframe" => %{"width" => 640, "height" => 480},
                 "custom" => %{"quiz_id" => "7"},
                 "lineItem" => %{
                   "scoreMaximum" => 100,
                   "label" => "Quiz",
                   "resourceId" => "quiz-7",
                   "tag" => "grade",
                   "gradesReleased" => true
                 },
                 "available" => %{
                   "startDateTime" => "2026-01-01T00:00:00Z",
                   "endDateTime" => "2026-06-30T23:59:59Z"
                 },
                 "submission" => %{"endDateTime" => "2026-06-15T23:59:59Z"}
               },
               %{
                 "type" => "file",
                 "url" => "https://example.com/syllabus.pdf",
                 "title" => "Syllabus",
                 "text" => "The course syllabus",
                 "icon" => icon_json,
                 "thumbnail" => thumbnail_json,
                 "mediaType" => "application/pdf",
                 "expiresAt" => "2026-12-31T23:59:59Z"
               },
               %{
                 "type" => "html",
                 "html" => "<p>Hello</p>",
                 "title" => "Greeting",
                 "text" => "A greeting"
               },
               %{
                 "type" => "image",
                 "url" => "https://example.com/diagram.png",
                 "title" => "Diagram",
                 "text" => "A diagram",
                 "icon" => icon_json,
                 "thumbnail" => thumbnail_json,
                 "width" => 800,
                 "height" => 600
               }
             ]
    end

    test "sends keys inside custom as written", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      item = LTIResourceLink.new!(custom: %{"course_id" => "12", :chapter_title => "Intro"})

      assert [%{"custom" => %{"course_id" => "12", "chapter_title" => "Intro"}}] =
               content_items(platform, launch, [item])

      item = %{item | custom: %{chapter_title: "Intro"}}

      assert [%{"custom" => %{"chapter_title" => "Intro"}}] =
               content_items(platform, launch, [item])
    end

    test "leaves out fields given nil, including nested ones", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

      item =
        Link.new!(
          url: "https://example.com",
          title: nil,
          icon: nil,
          window: [target_name: "docs", width: nil],
          iframe: [src: "https://example.com/embed", height: nil]
        )

      assert content_items(platform, launch, [item]) == [
               %{
                 "type" => "link",
                 "url" => "https://example.com",
                 "window" => %{"targetName" => "docs"},
                 "iframe" => %{"src" => "https://example.com/embed"}
               }
             ]
    end

    test "serializes a grade service line item", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      line_item = %Ltix.GradeService.LineItem{label: "Quiz 1", score_maximum: 10, tag: "grade"}

      assert [%{"lineItem" => %{"label" => "Quiz 1", "scoreMaximum" => 10, "tag" => "grade"}}] =
               content_items(platform, launch, [
                 LTIResourceLink.new!(line_item: line_item)
               ])
    end
  end

  describe "build_response/3 with plugins" do
    test "accepts a plugin's content item type listed in accept_types", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["https://vendor.example.com/poll"]},
          plugins: [{Modules, add: [Poll]}]
        )

      poll = Poll.new!(question: "Ready?", closes_at: ~U[2026-06-15 23:59:59Z])

      assert content_items(platform, launch, [poll]) == [
               %{
                 "type" => "https://vendor.example.com/poll",
                 "question" => "Ready?",
                 "closesAt" => "2026-06-15T23:59:59Z"
               }
             ]
    end

    test "camelizes the keys a content item type declares and sends other keys as written",
         %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["https://vendor.example.com/poll"]},
          plugins: [{Modules, add: [Poll]}]
        )

      poll =
        Poll.new!(
          question: "Ready?",
          window: [target_name: "poll"],
          choices: [%{choice_label: "Yes"}],
          results: %{first_choice: %{vote_count: 3}}
        )

      assert content_items(platform, launch, [poll]) == [
               %{
                 "type" => "https://vendor.example.com/poll",
                 "question" => "Ready?",
                 "window" => %{"targetName" => "poll"},
                 "choices" => [%{"choiceLabel" => "Yes"}],
                 "results" => %{"first_choice" => %{"voteCount" => 3}}
               }
             ]
    end

    test "checks a plugin's content item type against accept_types and presentation targets",
         %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{
            accept_types: ["link"],
            accept_presentation_document_targets: ["iframe"]
          },
          plugins: [{Modules, add: [Poll]}]
        )

      poll = Poll.new!(question: "Ready?", window: [target_name: "poll"])

      assert {:error,
              %Ltix.Errors.Invalid{
                errors: [
                  %ContentItemTypeNotAccepted{index: 0, type: "https://vendor.example.com/poll"},
                  %PresentationTargetNotAccepted{index: 0, target: "window"}
                ]
              }} = DeepLinking.build_response(launch, [poll])
    end

    test "rejects a content item type the plugin set doesn't provide", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["https://vendor.example.com/poll"]}
        )

      poll = Poll.new!(question: "Ready?")

      assert {:error, %InvalidContentItem{index: 0, value: ^poll} = error} =
               DeepLinking.build_response(launch, [poll])

      assert Exception.message(error) =~ "Content item at index 0 is not a content item"
    end

    test "serializes a plugin's property on ltiResourceLink", %{platform: platform} do
      plugins = [{Modules, add: [{Weight, unit: "points"}]}]
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking, plugins: plugins)

      assert {:ok, item} = LTIResourceLink.new(title: "Quiz", weight: 2, plugins: plugins)
      assert item.extensions == %{weight: 2}

      assert content_items(platform, launch, [item]) == [
               %{
                 "type" => "ltiResourceLink",
                 "title" => "Quiz",
                 "https://vendor.example.com/weight" => %{"value" => 2, "unit" => "points"}
               }
             ]
    end

    test "serializes a plugin's property on each of Deep Linking's other content item types", %{
      platform: platform
    } do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          plugins: [{Modules, add: [TestPlugins.ItemNote]}]
        )

      plugins = launch.plugins

      items = [
        Link.new!(url: "https://example.com/article", note: "n", plugins: plugins),
        File.new!(url: "https://example.com/syllabus.pdf", note: "n", plugins: plugins),
        HTMLFragment.new!(html: "<p>Hello</p>", note: "n", plugins: plugins),
        Image.new!(url: "https://example.com/diagram.png", note: "n", plugins: plugins)
      ]

      assert [%{"type" => "link"}, %{"type" => "file"}, %{"type" => "html"}, %{"type" => "image"}] =
               json = content_items(platform, launch, items)

      assert Enum.map(json, & &1["https://vendor.example.com/note"]) == ["n", "n", "n", "n"]
    end

    test "serializes an anonymous property a plugin adds with add_property/2",
         %{platform: platform} do
      build =
        &LTIResourceLink.add_property(&1,
          property: "https://vendor.example.com/difficulty",
          name: :difficulty
        )

      plugins = [{Modules, build: build}]
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking, plugins: plugins)
      item = LTIResourceLink.new!(title: "Quiz", difficulty: "hard", plugins: plugins)

      assert content_items(platform, launch, [item]) == [
               %{
                 "type" => "ltiResourceLink",
                 "title" => "Quiz",
                 "https://vendor.example.com/difficulty" => "hard"
               }
             ]
    end

    test "add_property/2 raises for missing or invalid options, and Ltix.Property.add/3 for a module that isn't a type with properties" do
      assert_raise InvalidOption, ~r/:property/, fn ->
        LTIResourceLink.add_property(Ltix.Plugin.new(), name: :difficulty)
      end

      assert_raise InvalidOption, ~r/:writes/, fn ->
        LTIResourceLink.add_property(Ltix.Plugin.new(),
          property: "https://vendor.example.com/difficulty",
          name: :difficulty,
          writes: [:delete]
        )
      end

      assert_raise ArgumentError, ~r/^Ltix.Launch doesn't take properties/, fn ->
        Ltix.Property.add(Ltix.Plugin.new(), Ltix.Launch, property: "x", name: :x)
      end

      assert_raise ArgumentError, ~r/^Ltix.Claim doesn't take properties/, fn ->
        Ltix.Property.add(Ltix.Plugin.new(), Ltix.Claim, property: "x", name: :x)
      end
    end

    test "a property module's use raises for an option value of the wrong type" do
      difficulty = "https://vendor.example.com/difficulty"

      for {opts, message} <- [
            {[property: "", name: :difficulty],
             "a property's :property option must be a non-empty string"},
            {[property: difficulty, name: "difficulty"],
             "a property's :name option must be an atom"},
            {[property: difficulty, name: :difficulty, writes: [:delete]],
             "a property's :writes option must be a list of :create and :update"},
            {[property: difficulty, name: :difficulty, schema: "string"],
             "a property's :schema option must be a Zoi schema"}
          ] do
        assert_raise ArgumentError, ~r/^#{Regex.escape(message)}/, fn ->
          Code.compile_quoted(
            quote do
              defmodule InvalidDifficulty do
                use Ltix.DeepLinking.ContentItem.LTIResourceLink, unquote(opts)
              end
            end
          )
        end
      end
    end

    test "leaves out a property the plugin set doesn't declare", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

      item =
        LTIResourceLink.new!(title: "Quiz", weight: 2, plugins: [{Modules, add: [Weight]}])

      assert content_items(platform, launch, [item]) == [
               %{"type" => "ltiResourceLink", "title" => "Quiz"}
             ]
    end

    test "plugins: replaces the launch's plugin set", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      item = %LTIResourceLink{extensions: %{weight: 2}}

      assert [%{"https://vendor.example.com/weight" => %{"value" => 2}}] =
               content_items(platform, launch, [item], plugins: [{Modules, add: [Weight]}])
    end

    test "reports two modules declaring one content item type", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

      assert {:error, %InvalidPluginSet{conflicts: [conflict]} = error} =
               DeepLinking.build_response(launch, [],
                 plugins: [{Modules, name: "Polls", add: [Poll, OtherPoll]}]
               )

      assert %Conflict{parties: [%Entry{module: Poll}, %Entry{module: OtherPoll}]} = conflict

      assert Exception.message(error) =~
               ~s[TestPlugins.Poll (Polls 1.0.0) and TestPlugins.OtherPoll (Polls 1.0.0) both declare the content item type "https://vendor.example.com/poll"]
    end

    test "reports two modules declaring one property", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

      assert {:error, %InvalidPluginSet{conflicts: [conflict]} = error} =
               DeepLinking.build_response(launch, [],
                 plugins: [{Modules, name: "Weights", add: [Weight, OtherWeight]}]
               )

      assert %Conflict{parties: [%Entry{module: Weight}, %Entry{module: OtherWeight}]} = conflict

      assert Exception.message(error) =~
               ~s(both declare the property "https://vendor.example.com/weight" on Ltix.DeepLinking.ContentItem.LTIResourceLink)
    end

    test "reports an anonymous property and a property module declaring one property",
         %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

      build =
        &LTIResourceLink.add_property(&1,
          property: "https://vendor.example.com/weight",
          name: :anonymous_weight
        )

      assert {:error, %InvalidPluginSet{} = error} =
               DeepLinking.build_response(launch, [],
                 plugins: [{Modules, name: "Weights", add: [Weight], build: build}]
               )

      assert Exception.message(error) ==
               ~s(TestPlugins.Weight \(Weights 1.0.0\) and an anonymous property of Weights 1.0.0 both declare the property "https://vendor.example.com/weight" on Ltix.DeepLinking.ContentItem.LTIResourceLink)
    end
  end

  describe "build_response/3 with Deep Linking line items" do
    test "an anonymous property a plugin adds with add_property/2 is in the response",
         %{platform: platform} do
      build =
        &Ltix.DeepLinking.LineItem.add_property(&1,
          property: "https://vendor.example.com/rubric_id",
          name: :rubric_id
        )

      plugins = [{Modules, build: build}]
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking, plugins: plugins)

      link =
        LTIResourceLink.new!(
          url: "https://tool.example.com/essays/7",
          line_item: [label: "Essay", score_maximum: 10, rubric_id: "r-1"],
          plugins: plugins
        )

      assert [%{"lineItem" => %{"https://vendor.example.com/rubric_id" => "r-1"}}] =
               content_items(platform, launch, [link])
    end

    test "a property of both line items is sent by the grade service and in the response",
         %{platform: platform} do
      plugins = [{Modules, add: [SubmissionReview]}]
      review = %{"reviewableStatus" => "Submitted"}
      client = GradeServiceFixtures.create_client(plugins: plugins)

      GradeServiceFixtures.stub_requests(fn "POST", body ->
        Map.put(body, "id", GradeServiceFixtures.line_item_url())
      end)

      line_item = %GradeService.LineItem{
        label: "Essay",
        score_maximum: 10,
        extensions: %{submission_review: %{reviewable_status: "Submitted"}}
      }

      assert {:ok, _created} = GradeService.create_line_item(client, line_item)
      assert_received {"POST", %{"submissionReview" => ^review}}

      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking, plugins: plugins)

      assert [
               %{
                 "lineItem" => %{
                   "label" => "Essay",
                   "scoreMaximum" => 10,
                   "submissionReview" => ^review
                 }
               }
             ] =
               content_items(platform, launch, [
                 LTIResourceLink.new!(line_item: line_item, plugins: plugins)
               ])
    end

    test "a create-only property is sent in a Deep Linking line item", %{platform: platform} do
      plugins = [{Modules, add: [Rubric]}]
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking, plugins: plugins)

      link =
        LTIResourceLink.new!(line_item: [score_maximum: 10, rubric: "rubric-7"], plugins: plugins)

      assert link.line_item.extensions == %{rubric: "rubric-7"}

      assert content_items(platform, launch, [link]) == [
               %{
                 "type" => "ltiResourceLink",
                 "lineItem" => %{
                   "scoreMaximum" => 10,
                   "https://vendor.example.com/rubric" => %{"id" => "rubric-7"}
                 }
               }
             ]
    end

    test "leaves out a property the plugin set doesn't declare", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      line_item = %LineItem{score_maximum: 10, extensions: %{rubric: "rubric-7"}}

      assert [%{"lineItem" => %{"scoreMaximum" => 10} = json}] =
               content_items(platform, launch, [LTIResourceLink.new!(line_item: line_item)])

      assert map_size(json) == 1
    end

    test "reports two modules declaring one property", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

      assert {:error, %InvalidPluginSet{conflicts: conflicts}} =
               DeepLinking.build_response(launch, [],
                 plugins: [{Modules, name: "Reviews", add: [SubmissionReview, OtherReview]}]
               )

      assert %Conflict{
               parties: [SubmissionReview, OtherReview],
               reason:
                 ~s(both declare the property "submissionReview" on Ltix.DeepLinking.LineItem)
             } in Enum.map(
               conflicts,
               &%{&1 | parties: Enum.map(&1.parties, fn entry -> entry.module end)}
             )
    end
  end

  describe "build_response/3 with response steps" do
    test "a step adds a claim to the response JWT", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          plugins: [{Modules, add: [{ItemCount, claim: "https://vendor.example.com/count"}]}]
        )

      {:ok, link} = Link.new(url: "https://example.com")
      assert {:ok, %Response{jwt: jwt} = response} = DeepLinking.build_response(launch, [link])
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, jwt)

      assert claims["https://vendor.example.com/count"] == 1
      assert claims[@lti <> "message_type"] == "LtiDeepLinkingResponse"
      assert response.claims == claims
      assert response.launch == launch
      assert response.errors == []
    end

    test "an anonymous step a plugin adds with add_step/2 changes the claims",
         %{platform: platform} do
      build =
        &Response.add_step(&1, fn response ->
          {:ok, put_in(response.claims["https://vendor.example.com/selected_by"], "tool")}
        end)

      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          plugins: [{Modules, build: build}]
        )

      assert {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(launch, [])
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, jwt)
      assert claims["https://vendor.example.com/selected_by"] == "tool"
    end

    test "returns a step's error", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

      assert {:error, %RuntimeError{message: "rejected"}} =
               DeepLinking.build_response(launch, [], plugins: [{Modules, add: [RejectResponse]}])
    end

    test "steps don't run for content items with errors", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

      assert {:error, %InvalidContentItem{}} =
               DeepLinking.build_response(launch, [%{}],
                 plugins: [{Modules, add: [RejectResponse]}]
               )
    end
  end

  describe "build_response/3 data claim" do
    test "returns the data from the settings", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{data: "echo-me"}
        )

      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(launch)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, jwt)

      assert claims[@dl <> "data"] == "echo-me"
    end

    test "omits data when not present in settings", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(launch)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, jwt)

      refute Map.has_key?(claims, @dl <> "data")
    end
  end

  describe "build_response/3 message options" do
    test "includes message and log in JWT", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

      {:ok, %Response{jwt: jwt}} =
        DeepLinking.build_response(launch, [], message: "Done", log: "debug info")

      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, jwt)

      assert claims[@dl <> "msg"] == "Done"
      assert claims[@dl <> "log"] == "debug info"
    end

    test "includes errormsg and errorlog in JWT", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

      {:ok, %Response{jwt: jwt}} =
        DeepLinking.build_response(launch, [],
          error_message: "Oops",
          error_log: "stack trace"
        )

      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, jwt)

      assert claims[@dl <> "errormsg"] == "Oops"
      assert claims[@dl <> "errorlog"] == "stack trace"
    end

    test "raises on unknown and invalid options", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      resource_link_context = Ltix.Test.build_launch(platform)

      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :msg is unknown", fn ->
        DeepLinking.build_response(launch, [], msg: "Done")
      end

      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :msg is unknown", fn ->
        DeepLinking.build_response(resource_link_context, [], msg: "Done")
      end

      error =
        assert_raise Ltix.Errors.Invalid.InvalidOption, fn ->
          DeepLinking.build_response(launch, [], log: 123)
        end

      assert %{key: :log, value: 123} = error
    end

    test "omits absent message options from JWT", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(launch)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(platform, jwt)

      refute Map.has_key?(claims, @dl <> "msg")
      refute Map.has_key?(claims, @dl <> "log")
      refute Map.has_key?(claims, @dl <> "errormsg")
      refute Map.has_key?(claims, @dl <> "errorlog")
    end
  end

  describe "build_response/3 type validation" do
    test "rejects item type not in accept_types", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["ltiResourceLink"]}
        )

      {:ok, link} = Link.new(url: "https://example.com")

      assert {:error, %ContentItemTypeNotAccepted{index: 0, type: "link"} = error} =
               DeepLinking.build_response(launch, [link])

      assert Exception.message(error) ==
               ~s(Content item type "link" at index 0 is not accepted; ) <>
                 ~s(platform accepts: ["ltiResourceLink"])
    end
  end

  describe "build_response/3 multiplicity validation" do
    test "rejects multiple items when accept_multiple is false", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["link"], accept_multiple: false}
        )

      {:ok, first} = Link.new(url: "https://a.com")
      {:ok, second} = Link.new(url: "https://b.com")

      assert {:error, %ContentItemsExceedLimit{index: 1, count: 2} = error} =
               DeepLinking.build_response(launch, [first, second])

      assert Exception.message(error) ==
               "2 content items returned but platform does not accept multiple items"
    end

    test "allows single item when accept_multiple is false", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["link"], accept_multiple: false}
        )

      {:ok, link} = Link.new(url: "https://a.com")

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [link])
    end

    test "allows multiple items when accept_multiple is nil", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["link"], accept_multiple: nil}
        )

      {:ok, first} = Link.new(url: "https://a.com")
      {:ok, second} = Link.new(url: "https://b.com")

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [first, second])
    end
  end

  describe "build_response/3 line item validation" do
    test "rejects line_item when accept_line_item is false", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["ltiResourceLink"], accept_line_item: false}
        )

      {:ok, item} = LTIResourceLink.new(line_item: %{score_maximum: 100})

      assert {:error, %LineItemNotAccepted{index: 0}} =
               DeepLinking.build_response(launch, [item])
    end

    test "allows line_item when accept_line_item is true", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["ltiResourceLink"], accept_line_item: true}
        )

      {:ok, item} = LTIResourceLink.new(line_item: %{score_maximum: 100})

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [item])
    end

    test "allows LTIResourceLink without line_item when accept_line_item is false", %{
      platform: platform
    } do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["ltiResourceLink"], accept_line_item: false}
        )

      {:ok, item} = LTIResourceLink.new(url: "https://tool.example.com")

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [item])
    end
  end

  describe "build_response/3 presentation target validation" do
    test "rejects presentations not in accept_presentation_document_targets", %{
      platform: platform
    } do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_presentation_document_targets: ["iframe"]}
        )

      {:ok, link} =
        Link.new(
          url: "https://example.com",
          iframe: [src: "https://example.com/embed"],
          embed: [html: "<p>Hi</p>"]
        )

      {:ok, resource} = LTIResourceLink.new(window: [target_name: "quiz"])

      assert {:error,
              %Ltix.Errors.Invalid{
                errors: [
                  %PresentationTargetNotAccepted{
                    index: 0,
                    target: "embed",
                    accept_presentation_document_targets: ["iframe"]
                  },
                  %PresentationTargetNotAccepted{index: 1, target: "window"} = error
                ]
              }} = DeepLinking.build_response(launch, [link, resource])

      assert Exception.message(error) =~ ~s(index 1 uses presentation target "window")
    end

    test "accepts items without a presentation when no targets are accepted", %{
      platform: platform
    } do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_presentation_document_targets: []}
        )

      {:ok, link} = Link.new(url: "https://example.com")

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [link])
    end
  end

  describe "build_response/3 media type validation" do
    setup %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_media_types: "image/*, text/html"}
        )

      %{launch: launch}
    end

    test "accepts a file whose media type the platform lists", %{launch: launch} do
      file = File.new!(url: "https://example.com/a.html", media_type: "text/html")

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [file])
    end

    test "accepts a file whose type the platform lists with any subtype", %{launch: launch} do
      file = File.new!(url: "https://example.com/a.png", media_type: "image/png")

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [file])
    end

    test "accepts any file when the platform accepts */*", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_media_types: "*/*"}
        )

      file = File.new!(url: "https://example.com/f.pdf", media_type: "application/pdf")

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [file])
    end

    test "matches media types in any case", %{launch: launch} do
      file = File.new!(url: "https://example.com/a.html", media_type: "Text/HTML")

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [file])
    end

    test "matches media types without their parameters", %{launch: launch} do
      file = File.new!(url: "https://example.com/a.html", media_type: "text/html; charset=utf-8")

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [file])
    end

    test "accepts a file without a media type", %{launch: launch} do
      file = File.new!(url: "https://example.com/a")

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [file])
    end

    test "rejects files whose media type is not accepted", %{launch: launch} do
      pdf = File.new!(url: "https://example.com/f.pdf", media_type: "application/pdf")
      video = File.new!(url: "https://example.com/v.mp4", media_type: "video/mp4")

      assert {:error,
              %Ltix.Errors.Invalid{
                errors: [
                  %MediaTypeNotAccepted{
                    index: 0,
                    media_type: "application/pdf",
                    accept_media_types: "image/*, text/html"
                  } = error,
                  %MediaTypeNotAccepted{index: 1, media_type: "video/mp4"}
                ]
              }} = DeepLinking.build_response(launch, [pdf, video])

      assert Exception.message(error) =~ ~s(index 0 has media type "application/pdf")
    end

    test "cites the Deep Linking settings in the error message", %{launch: launch} do
      pdf = File.new!(url: "https://example.com/f.pdf", media_type: "application/pdf")

      assert {:error, %MediaTypeNotAccepted{} = error} = DeepLinking.build_response(launch, [pdf])

      assert Exception.message(error) ==
               ~s(Content item at index 0 has media type "application/pdf", which the platform ) <>
                 ~s(does not accept. Accepted media types are "image/*, text/html")
    end

    test "accepts any media type when the platform lists none", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      file = File.new!(url: "https://example.com/v.mp4", media_type: "video/mp4")

      assert {:ok, %Response{}} = DeepLinking.build_response(launch, [file])
    end
  end

  describe "build_response/3 with several violations" do
    test "returns every violation, identifying each item", %{platform: platform} do
      launch =
        Ltix.Test.build_launch(platform,
          message_type: :deep_linking,
          deep_linking_settings: %{
            accept_types: ["ltiResourceLink"],
            accept_multiple: false,
            accept_line_item: false
          }
        )

      {:ok, link} = Link.new(url: "https://example.com")
      {:ok, resource} = LTIResourceLink.new(line_item: [score_maximum: 10])
      {:ok, file} = File.new(url: "https://example.com/f.pdf")

      assert {:error, %Ltix.Errors.Invalid{errors: errors} = error} =
               DeepLinking.build_response(launch, [link, resource, file])

      assert [
               %ContentItemTypeNotAccepted{
                 index: 0,
                 type: "link",
                 accept_types: ["ltiResourceLink"]
               },
               %LineItemNotAccepted{index: 1},
               %ContentItemTypeNotAccepted{index: 2, type: "file"},
               %ContentItemsExceedLimit{index: 1, count: 3}
             ] = errors

      assert Exception.message(error) =~ "Content item at index 1 includes a line_item"
    end
  end

  describe "build_response/3 malformed items" do
    test "rejects a plain map as an undeclared content item type", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      item = %{"type" => "link", "url" => "https://example.com"}

      assert {:error, %InvalidContentItem{index: 0, value: ^item} = error} =
               DeepLinking.build_response(launch, [item])

      assert Exception.message(error) ==
               "Content item at index 0 is not a content item, " <>
                 ~s(got %{"type" => "link", "url" => "https://example.com"})
    end

    test "returns an error for items that are not a list", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      {:ok, link} = Link.new(url: "https://example.com")

      assert {:error, %InvalidContentItem{index: nil, value: ^link} = error} =
               DeepLinking.build_response(launch, link)

      assert Exception.message(error) =~ "Content items must be a list"
    end

    test "groups every malformed item", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      {:ok, link} = Link.new(url: "https://example.com")

      assert {:error,
              %Ltix.Errors.Invalid{
                errors: [
                  %InvalidContentItem{index: 1, value: %{}},
                  %InvalidContentItem{index: 2, value: nil}
                ]
              }} = DeepLinking.build_response(launch, [link, %{}, nil])
    end
  end

  describe "build_response/3 telemetry" do
    setup do
      ref = make_ref()

      :telemetry.attach_many(
        ref,
        [
          [:ltix, :deep_linking, :build_response, :start],
          [:ltix, :deep_linking, :build_response, :stop]
        ],
        &__MODULE__.forward_own_event/4,
        {self(), ref}
      )

      on_exit(fn -> :telemetry.detach(ref) end)
      %{ref: ref}
    end

    test "reports the item count and types", %{platform: platform, ref: ref} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      {:ok, link} = Link.new(url: "https://example.com")
      {:ok, image} = Image.new(url: "https://example.com/i.png")

      {:ok, _} = DeepLinking.build_response(launch, [link, image, link])

      assert_received {^ref, :start, %{item_count: 3, item_types: ["link", "image"]}}
      assert_received {^ref, :stop, %{item_count: 3, item_types: ["link", "image"]}}
    end

    test "emits start and stop events for calls that return an error", %{
      platform: platform,
      ref: ref
    } do
      deep_linking = Ltix.Test.build_launch(platform, message_type: :deep_linking)
      resource_link = Ltix.Test.build_launch(platform)

      {:error, _} = DeepLinking.build_response(deep_linking, :not_a_list)
      assert_received {^ref, :start, %{item_count: 0, item_types: []}}
      assert_received {^ref, :stop, _}

      {:error, _} = DeepLinking.build_response(resource_link, [])
      assert_received {^ref, :start, %{item_count: 0, item_types: []}}
      assert_received {^ref, :stop, %{item_count: 0, item_types: []}}
    end
  end

  describe "build_response!/3" do
    test "returns the response", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform, message_type: :deep_linking)

      assert %Response{return_url: "https://platform.example.com/deep_links"} =
               DeepLinking.build_response!(launch, [], message: "Done")
    end

    test "raises the error build_response/3 returns", %{platform: platform} do
      launch = Ltix.Test.build_launch(platform)

      assert_raise InvalidMessageType, fn -> DeepLinking.build_response!(launch) end
    end
  end
end
