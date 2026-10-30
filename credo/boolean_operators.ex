defmodule Ltix.Credo.BooleanOperators do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Write `&&`, `||`, and `!` outside guards.

          if valid? && !expired?, do: :ok

      Guards accept only `and`, `or`, and `not`, so they keep them. `not in`
      is its own operator, so it stays everywhere.
      """
    ]

  @replacements %{and: "&&", or: "||", not: "!"}

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, context).issues
  end

  # Skips the guard, the last argument of `when`.
  defp walk({:when, _, arguments}, context) do
    {{:__block__, [], Enum.drop(arguments, -1)}, context}
  end

  defp walk({:not, _, [{:in, _, _} = membership]}, context), do: {membership, context}

  defp walk({operator, meta, arguments} = ast, context)
       when is_map_key(@replacements, operator) and is_list(arguments) do
    issue =
      format_issue(context,
        message: "Write `#{@replacements[operator]}` in place of `#{operator}` outside guards.",
        trigger: Atom.to_string(operator),
        line_no: meta[:line],
        column: meta[:column]
      )

    {ast, put_issue(context, issue)}
  end

  defp walk(ast, context), do: {ast, context}
end
