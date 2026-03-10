# Building Scores

Beyond posting a final grade, you can track student progress, award
extra credit, and attach feedback. This cookbook walks through common
scoring scenarios.

## Posting a final grade

Set both progress fields to their "done" values so the platform
records the grade:

```elixir
{:ok, score} = Ltix.GradeService.Score.new(
  user_id: user_id,
  score_given: 92,
  score_maximum: 100,
  activity_progress: :completed,
  grading_progress: :fully_graded
)
```

> #### Use `:fully_graded` for final scores {: .warning}
>
> Platforms may ignore scores with any other `grading_progress` value.
> If you want the grade to appear in the gradebook, always use
> `:fully_graded`.

## Tracking progress without a grade

Report that a student has started an activity before you have a score
to post:

```elixir
{:ok, score} = Ltix.GradeService.Score.new(
  user_id: user_id,
  activity_progress: :started,
  grading_progress: :not_ready
)
```

Update the progress as the student works through the activity:

```elixir
{:ok, score} = Ltix.GradeService.Score.new(
  user_id: user_id,
  activity_progress: :in_progress,
  grading_progress: :pending
)
```

## Awarding extra credit

`score_given` may exceed `score_maximum`:

```elixir
{:ok, score} = Ltix.GradeService.Score.new(
  user_id: user_id,
  score_given: 110,
  score_maximum: 100,
  activity_progress: :completed,
  grading_progress: :fully_graded
)
```

## Including feedback

Add a plain-text comment visible to both student and instructor:

```elixir
{:ok, score} = Ltix.GradeService.Score.new(
  user_id: user_id,
  score_given: 75,
  score_maximum: 100,
  activity_progress: :completed,
  grading_progress: :fully_graded,
  comment: "Good work on part 2, but review section 3."
)
```

## Choosing progress values

### Activity progress

| Value | When to use |
|-------|-------------|
| `:initialized` | Student hasn't started yet, or you're resetting |
| `:started` | Student opened the activity |
| `:in_progress` | Student is working on it |
| `:submitted` | Student submitted but may resubmit |
| `:completed` | Student is done |

### Grading progress

| Value | When to use |
|-------|-------------|
| `:fully_graded` | Final grade, ready for the gradebook |
| `:pending` | Auto-grading in progress |
| `:pending_manual` | Waiting for instructor review |
| `:failed` | Grading could not complete |
| `:not_ready` | No grading happening yet |

> #### Timestamps {: .info}
>
> `Score.new/1` auto-generates a timestamp if you don't provide one.
> You can pass an explicit `:timestamp` for testing or replays.
