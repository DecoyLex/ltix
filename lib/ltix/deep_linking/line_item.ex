defmodule Ltix.DeepLinking.LineItem do
  @moduledoc """
  A line item for the platform to create along with an
  `Ltix.DeepLinking.ContentItem.LTIResourceLink`.

  A line item has one score per user for one activity. The platform decides
  where the scores appear, usually as a gradebook column. A platform can ignore
  a Deep Linking line item.

  [Line items](`m:Ltix.DeepLinking.ContentItem.LTIResourceLink#module-line-items`)
  lists the forms the link's `line_item` takes.

  ```elixir
  {:ok, link} =
    Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
      url: "https://tool.example.com/essays/7",
      line_item: [label: "Essay 7", score_maximum: 100]
    )
  ```

  ## Properties

  Plugins add properties to Deep Linking line items, such as a submission
  review, with `Ltix.Property`. Pass a property by its name with the line
  item's fields, and read it from `extensions`.

  ```elixir
  {:ok, link} =
    Ltix.DeepLinking.ContentItem.LTIResourceLink.new(
      url: "https://tool.example.com/essays/7",
      line_item: [
        label: "Essay 7",
        score_maximum: 100,
        submission_review: %Review.SubmissionReview{reviewable_status: ["Submitted"]}
      ]
    )

  link.line_item.extensions.submission_review.reviewable_status
  #=> ["Submitted"]
  ```

  [Add a property to Deep Linking line items](writing-deep-linking-plugins.md#add-a-property-to-deep-linking-line-items)
  shows the Submission Review property.

  ## Fields

    * `:score_maximum` - the maximum score, greater than 0 (required)
    * `:label` - the line item's label
    * `:resource_id` - the tool's identifier for the resource
    * `:tag` - the tool's qualifier for the line item, such as `"grade"`
    * `:grades_released` - whether the tool asks the platform to release
      grades to learners
  """

  use Ltix.Provider, hook: [Ltix.Property]

  alias Ltix.GradeService

  # [DL, LTI Resource Link](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#lti-resource-link)
  use Ltix.Type,
    json_keys: :camel_case,
    fields: [
      score_maximum: GradeService.LineItem.score_maximum_schema(),
      label: Zoi.optional(GradeService.LineItem.label_schema()),
      resource_id:
        Zoi.string(description: "The tool's identifier for the resource.") |> Zoi.optional(),
      tag:
        Zoi.string(description: "The tool's qualifier for the line item, such as `\"grade\"`.")
        |> Zoi.optional(),
      grades_released:
        Zoi.boolean(
          description: "Whether the tool asks the platform to release grades to learners."
        )
        |> Zoi.optional()
    ]

  @doc """
  Adds an anonymous property of Deep Linking line items to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
