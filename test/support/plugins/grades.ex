defmodule TestPlugins.SubmissionType do
  @moduledoc false
  # A create-only line item property, as an atom-keyed map.
  use Ltix.GradeService.LineItem,
    property: "https://vendor.example.com/submission_type",
    name: :submission_type,
    writes: [:create]

  @impl Ltix.Property
  def parse(%{"type" => type}, _opts), do: {:ok, %{type: type}}
  def parse(_json, _opts), do: {:error, "must be an object with a type"}

  @impl Ltix.Property
  def serialize(%{type: type}, _opts), do: %{"type" => type}
end

defmodule TestPlugins.OtherSubmissionType do
  @moduledoc false
  # Declares the property `TestPlugins.SubmissionType` declares.
  use Ltix.GradeService.LineItem,
    property: "https://vendor.example.com/submission_type",
    name: :other_submission_type
end

defmodule TestPlugins.LaunchUrl do
  @moduledoc false
  # A read-only line item property.
  use Ltix.GradeService.LineItem,
    property: "https://vendor.example.com/launch_url",
    name: :launch_url,
    writes: []

  @impl Ltix.Property
  def parse(url, _opts), do: {:ok, URI.parse(url)}

  @impl Ltix.Property
  def serialize(uri, _opts), do: URI.to_string(uri)
end

defmodule TestPlugins.ScoreSubmission do
  @moduledoc false
  # A score property. Its extension is the submission's data, sent with the
  # submission type in its `:submission_type` option.
  use Ltix.GradeService.Score,
    property: "https://vendor.example.com/submission",
    name: :vendor_submission

  @impl Ltix.Property
  def serialize(data, opts),
    do: %{"submission_data" => data, "submission_type" => Keyword.fetch!(opts, :submission_type)}
end

defmodule TestPlugins.ResultFeedback do
  @moduledoc false
  # A result property, as an atom-keyed map.
  use Ltix.GradeService.Result,
    property: "https://vendor.example.com/feedback",
    name: :feedback

  @impl Ltix.Property
  def parse(%{"text" => text}, _opts), do: {:ok, %{text: text}}

  @impl Ltix.Property
  def serialize(%{text: text}, _opts), do: %{"text" => text}
end

defmodule TestPlugins.SubmissionReview do
  @moduledoc false
  # A Submission Review-like property on line items and Deep Linking line
  # items, as an atom-keyed map.
  use Ltix.GradeService.LineItem,
    property: "submissionReview",
    name: :submission_review

  use Ltix.DeepLinking.LineItem

  @impl Ltix.Property
  def parse(json, _opts) when is_map(json),
    do: {:ok, %{url: json["url"], reviewable_status: json["reviewableStatus"]}}

  @impl Ltix.Property
  def serialize(review, _opts) do
    for {key, value} <- [{"url", review[:url]}, {"reviewableStatus", review[:reviewable_status]}],
        value != nil,
        into: %{},
        do: {key, value}
  end
end

defmodule TestPlugins.Rubric do
  @moduledoc false
  # A create-only property on line items and Deep Linking line items. Its
  # extension is the rubric's ID.
  use Ltix.GradeService.LineItem,
    property: "https://vendor.example.com/rubric",
    name: :rubric,
    writes: [:create]

  use Ltix.DeepLinking.LineItem

  @impl Ltix.Property
  def serialize(id, _opts), do: %{"id" => id}
end

defmodule TestPlugins.OtherReview do
  @moduledoc false
  # Declares the Deep Linking line item property `TestPlugins.SubmissionReview`
  # declares.
  use Ltix.DeepLinking.LineItem,
    property: "submissionReview",
    name: :other_review
end

defmodule TestPlugins.Tagged do
  @moduledoc false
  # A line item property sent as its value prefixed with the `:tag` option.
  use Ltix.GradeService.LineItem,
    property: "https://vendor.example.com/tagged",
    name: :tagged

  @impl Ltix.Property
  def parse(json, opts) do
    prefix = "#{opts[:tag]}:"

    case json do
      ^prefix <> value -> {:ok, value}
      _other -> {:error, "must start with #{prefix}"}
    end
  end

  @impl Ltix.Property
  def serialize(value, opts), do: "#{opts[:tag]}:#{value}"
end

defmodule TestPlugins.OtherSubmission do
  @moduledoc false
  # Declares the score property `TestPlugins.ScoreSubmission` declares.
  use Ltix.GradeService.Score,
    property: "https://vendor.example.com/submission",
    name: :other_submission
end

defmodule TestPlugins.OtherFeedback do
  @moduledoc false
  # Declares the result property `TestPlugins.ResultFeedback` declares.
  use Ltix.GradeService.Result,
    property: "https://vendor.example.com/feedback",
    name: :other_feedback
end

defmodule TestPlugins.LabelProperty do
  @moduledoc false
  # Declares a line item property with the JSON name of the standard field
  # `label`.
  use Ltix.GradeService.LineItem,
    property: "label",
    name: :label_property
end

defmodule TestPlugins.SubmissionKind do
  @moduledoc false
  # Declares the name `TestPlugins.SubmissionType` declares, for another
  # property.
  use Ltix.GradeService.LineItem,
    property: "https://vendor.example.com/submission_kind",
    name: :submission_type
end

defmodule TestPlugins.LabelName do
  @moduledoc false
  # Declares a line item property named like the standard field `label`.
  use Ltix.GradeService.LineItem,
    property: "https://vendor.example.com/label",
    name: :label
end

defmodule TestPlugins.PluginsName do
  @moduledoc false
  # Declares a score property named like the `:plugins` option.
  use Ltix.GradeService.Score,
    property: "https://vendor.example.com/plugins",
    name: :plugins
end
