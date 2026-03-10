# Using Canvas Grade Extensions

Canvas supports extra properties on line items and scores. Pass them
via the `:extensions` option when creating line items or posting
scores.

## Submission type on line item create

Set the Canvas assignment's submission type when creating a line item:

```elixir
{:ok, item} = Ltix.GradeService.create_line_item(client,
  label: "External Assignment",
  score_maximum: 100,
  extensions: %{
    "https://canvas.instructure.com/lti/submission_type" => %{
      "type" => "external_tool",
      "external_tool_url" => "https://my.tool.url/launch"
    }
  }
)
```

## Submission metadata on scores

Attach submission details when posting a score:

```elixir
{:ok, score} = Ltix.GradeService.Score.new(
  user_id: user_id,
  score_given: 85,
  score_maximum: 100,
  activity_progress: :completed,
  grading_progress: :fully_graded,
  extensions: %{
    "https://canvas.instructure.com/lti/submission" => %{
      "new_submission" => true,
      "submission_type" => "online_url",
      "submission_data" => "https://example.com/student-work"
    }
  }
)
```

See [Canvas LTI documentation](https://canvas.instructure.com/doc/api/score.html)
for the full list of supported submission fields.
