defmodule Ltix.GradeService.Result do
  @moduledoc """
  A result record from the platform's gradebook.

  Results are read-only. The platform provides them via the result
  service. Each result represents the current grade for a specific
  line item and user.

  When `result_maximum` is `nil`, consumers should treat it as 1
  per the spec default.

  Plugins add properties to results with `Ltix.Property`. Read a property from
  `extensions` by its name, as in `result.extensions.feedback`.

  ## Examples

  ```elixir
  {:ok, [result | _]} = Ltix.GradeService.list_results(client, line_item: item)

  result.result_score
  #=> 0.83
  ```
  """

  use Ltix.Provider, hook: [Ltix.Property]

  # [AGS, Media type and schema](https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec#media-type-and-schema)
  use Ltix.Type,
    json_keys: :camel_case,
    fields: [
      id: Zoi.string() |> Zoi.optional(),
      score_of: Zoi.string() |> Zoi.optional(),
      user_id: Zoi.string() |> Zoi.optional(),
      result_score: Zoi.number() |> Zoi.optional(),
      result_maximum: Zoi.number() |> Zoi.optional(),
      scoring_user_id: Zoi.string() |> Zoi.optional(),
      comment: Zoi.string() |> Zoi.optional()
    ]

  @doc """
  Adds an anonymous property of results to a plugin.

  ## Options

  #{Zoi.describe(Ltix.Property.options_schema())}
  """
  @spec add_property(Ltix.Plugin.t(), keyword()) :: Ltix.Plugin.t()
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
end
