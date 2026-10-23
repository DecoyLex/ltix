defmodule Ltix.DeepLinking.ContentItem.LTIResourceLinkTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking.ContentItem.LTIResourceLink
  alias Ltix.DeepLinking.LineItem
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.GradeService
  alias TestPlugins.Modules
  alias TestPlugins.SubmissionReview
  alias TestPlugins.SubmissionType

  @plugins [{Modules, add: [SubmissionReview, SubmissionType]}]

  doctest LTIResourceLink

  describe "new/1" do
    test "rejects an iframe src, which only links have" do
      assert {:error,
              %InvalidField{field: [:iframe, :src], value: "https://tool.example.com/embed"}} =
               LTIResourceLink.new(iframe: [src: "https://tool.example.com/embed", width: 640])
    end

    test "accepts custom as a keyword list or a map with atom or string keys" do
      expected = %{"chapter" => "12", "page" => "42"}

      assert {:ok, %LTIResourceLink{custom: ^expected}} =
               LTIResourceLink.new(custom: [chapter: "12", page: "42"])

      assert {:ok, %LTIResourceLink{custom: ^expected}} =
               LTIResourceLink.new(custom: %{:chapter => "12", "page" => "42"})
    end

    test "describes the problem with an invalid custom option" do
      assert {:error, %InvalidField{field: :custom} = error} =
               LTIResourceLink.new(custom: "chapter=12")

      assert Exception.message(error) ==
               ~s(Ltix.DeepLinking.ContentItem.LTIResourceLink field :custom must be a map or keyword list \(got "chapter=12"\))

      assert {:error, %InvalidField{field: [:custom, 12]} = error} =
               LTIResourceLink.new(custom: %{12 => "chapter"})

      assert Exception.message(error) ==
               ~s(Ltix.DeepLinking.ContentItem.LTIResourceLink field [:custom, 12] must be keyed by a string or atom \(got "chapter"\))
    end

    test "returns error when custom contains non-string values" do
      assert {:error, %InvalidField{field: [:custom, "key"], value: 123} = error} =
               LTIResourceLink.new(custom: %{"key" => 123})

      assert Exception.message(error) ==
               ~s(Ltix.DeepLinking.ContentItem.LTIResourceLink field [:custom, "key"] must be a string \(got 123\))
    end

    test "returns every invalid field together" do
      assert {:error, %Ltix.Errors.Invalid{errors: errors}} =
               LTIResourceLink.new(custom: %{"key" => 123}, line_item: %{score_maximum: 0})

      assert Enum.sort(Enum.map(errors, & &1.field)) ==
               [[:custom, "key"], [:line_item, :score_maximum]]
    end

    test "returns error when line_item missing score_maximum" do
      assert {:error, %InvalidField{} = error} =
               LTIResourceLink.new(line_item: %{label: "Quiz"})

      assert Exception.message(error) =~ "[:line_item, :score_maximum]"
      assert Exception.message(error) =~ "is required"
    end

    test "copies the five shared fields of a grade service line item" do
      line_item = %GradeService.LineItem{
        label: "Quiz 1",
        score_maximum: 10,
        resource_id: "quiz-1",
        tag: "grade",
        grades_released: true
      }

      assert {:ok, %LTIResourceLink{line_item: copied}} =
               LTIResourceLink.new(line_item: line_item)

      assert copied == %LineItem{
               label: "Quiz 1",
               score_maximum: 10,
               resource_id: "quiz-1",
               tag: "grade",
               grades_released: true
             }
    end

    test "returns an error for each grade service line item field that deep linking can't include" do
      line_item = %GradeService.LineItem{
        id: "https://lms.example.com/lineitems/1",
        label: "Quiz 1",
        score_maximum: 10,
        resource_link_id: "link-1",
        start_date_time: ~U[2026-01-01 00:00:00Z],
        end_date_time: ~U[2026-06-30 23:59:59Z]
      }

      assert {:error, %Ltix.Errors.Invalid{errors: errors}} =
               LTIResourceLink.new(line_item: line_item)

      assert Enum.sort(Enum.map(errors, & &1.field)) == [
               [:line_item, :end_date_time],
               [:line_item, :id],
               [:line_item, :resource_link_id],
               [:line_item, :start_date_time]
             ]
    end

    test "returns an error for an end_date_time on a grade service line item" do
      line_item = %GradeService.LineItem{
        score_maximum: 10,
        end_date_time: ~U[2026-06-30 23:59:59Z]
      }

      assert {:error, %InvalidField{field: [:line_item, :end_date_time], reason: :unknown}} =
               LTIResourceLink.new(line_item: line_item)
    end

    test "copies a grade service line item's property that Deep Linking line items have" do
      review = %{url: "https://tool.example.com/review"}

      line_item = %GradeService.LineItem{
        score_maximum: 10,
        extensions: %{submission_review: review}
      }

      assert {:ok, %LTIResourceLink{line_item: copied}} =
               LTIResourceLink.new(line_item: line_item, plugins: @plugins)

      assert copied == %LineItem{score_maximum: 10, extensions: %{submission_review: review}}
    end

    test "returns an error for a grade service line item's property that Deep Linking line items don't have" do
      line_item = %GradeService.LineItem{
        score_maximum: 10,
        extensions: %{submission_type: %{type: "external_tool"}}
      }

      assert {:error, %InvalidField{} = error} =
               LTIResourceLink.new(line_item: line_item, plugins: @plugins)

      assert %InvalidField{
               struct: LTIResourceLink,
               field: [:line_item, :submission_type],
               value: %{type: "external_tool"},
               reason: :unknown
             } = error
    end

    test "returns every line item error with the content item's other errors" do
      line_item = %GradeService.LineItem{
        id: "https://lms.example.com/lineitems/1",
        score_maximum: 0,
        extensions: %{submission_type: %{type: "external_tool"}}
      }

      assert {:error, %Ltix.Errors.Invalid{errors: errors}} =
               LTIResourceLink.new(line_item: line_item, title: 7, plugins: @plugins)

      assert Enum.sort(Enum.map(errors, & &1.field)) == [
               :title,
               [:line_item, :id],
               [:line_item, :score_maximum],
               [:line_item, :submission_type]
             ]
    end

    test "keeps the extensions of a Deep Linking line item" do
      line_item = %LineItem{score_maximum: 10, extensions: %{submission_review: %{url: "u"}}}

      assert {:ok, %LTIResourceLink{line_item: ^line_item}} =
               LTIResourceLink.new(line_item: line_item)
    end

    test "takes a Deep Linking line item's property names with its fields" do
      assert {:ok, %LTIResourceLink{line_item: line_item}} =
               LTIResourceLink.new(
                 line_item: [score_maximum: 10, submission_review: %{url: "u"}],
                 plugins: @plugins
               )

      assert line_item == %LineItem{
               score_maximum: 10,
               extensions: %{submission_review: %{url: "u"}}
             }
    end

    test "returns an error for a name that's neither a field nor a property" do
      assert {:error, %Ltix.Errors.Invalid{errors: errors}} =
               LTIResourceLink.new(
                 line_item: [score_maximum: 10, submission_type: %{type: "none"}],
                 wieght: 2,
                 plugins: @plugins
               )

      assert Enum.sort(Enum.map(errors, &{&1.field, &1.reason})) == [
               {:wieght, :unknown},
               {[:line_item, :submission_type], :unknown}
             ]
    end

    test "checks the fields of a Deep Linking line item" do
      assert {:error, %InvalidField{field: [:line_item, :score_maximum], value: 0}} =
               LTIResourceLink.new(line_item: %LineItem{score_maximum: 0})
    end

    test "rejects line item labels and maximum scores the grade service rejects" do
      assert {:error,
              %InvalidField{
                field: [:line_item, :label],
                value: " ",
                reason: "must not be blank"
              }} = LTIResourceLink.new(line_item: [label: " ", score_maximum: 10])

      assert {:error, %InvalidField{field: [:line_item, :score_maximum], value: 0}} =
               LTIResourceLink.new(line_item: [label: "Quiz", score_maximum: 0])
    end

    test "rejects time windows given as strings" do
      assert {:error,
              %InvalidField{
                field: [:submission, :end_date_time],
                value: "2026-06-15T23:59:59Z"
              }} =
               LTIResourceLink.new(submission: [end_date_time: "2026-06-15T23:59:59Z"])
    end
  end
end
