defmodule Ltix.Credo.DoctestOutput do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      A doctest shows the value an expression returns.

          iex> Ltix.Plugin.new(name: "My Library")
          %Ltix.Plugin{name: "My Library", version: nil}

      A comparison that shows `true` hides the value from the reader.
      """
    ]

  @prompt ~r/^\s*(?<prompt>iex|\.\.\.)>(?<expression>.*)$/
  @comparison ~r/==|!=|=~|match\?\(/

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)

    {_expression, issue_lines} = Enum.reduce(SourceFile.lines(source_file), {nil, []}, &line/2)

    for line_no <- Enum.reverse(issue_lines) do
      format_issue(context, message: "Show the value in place of a comparison.", line_no: line_no)
    end
  end

  # Tracks the current expression as `{first_line_no, text}`.
  defp line({line_no, line}, {expression, issue_lines}) do
    case Regex.named_captures(@prompt, line) do
      %{"prompt" => "iex", "expression" => text} -> {{line_no, text}, issue_lines}
      %{"expression" => text} when expression != nil -> {continue(expression, text), issue_lines}
      _output -> {nil, output(expression, String.trim(line), issue_lines)}
    end
  end

  defp continue({line_no, text}, more), do: {line_no, text <> "\n" <> more}

  defp output({line_no, text}, result, issue_lines) when result in ["true", "false"] do
    if text =~ @comparison, do: [line_no | issue_lines], else: issue_lines
  end

  defp output(_expression, _result, issue_lines), do: issue_lines
end
