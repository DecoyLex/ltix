defmodule Ltix.Credo.DocCodeFences do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Code in a doc goes in a fenced block that names its language.

          @doc \"\"\"
          Runs the example.

          ```elixir
          iex> Example.run()
          :ok
          ```
          \"\"\"
      """
    ]

  @open ~r/^\s*@(moduledoc|doc|typedoc|shortdoc)\s+(~[sS])?"""\s*$/
  @close ~r/^(?<indent>\s*)"""/
  @fence ~r/^\s*```/
  @bare_fence ~r/^\s*```\s*$/
  @list_item ~r/^(\s*)([*+-]|\d+\.)(\s+)/
  @doc_attributes [:moduledoc, :doc, :typedoc, :shortdoc]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)

    attribute_lines = Credo.Code.prewalk(source_file, &attribute_line/2, MapSet.new())

    source_file
    |> SourceFile.lines()
    |> docs(attribute_lines, [])
    |> Enum.flat_map(&issues/1)
    |> Enum.map(&issue(context, &1))
  end

  # Returns each heredoc doc as its lines and the indentation its closing
  # delimiter sets.
  defp docs([], _attribute_lines, acc), do: Enum.reverse(acc)

  defp docs([{line_no, line} | rest], attribute_lines, acc) do
    if MapSet.member?(attribute_lines, line_no) && line =~ @open do
      {body, [{_close_no, close} | after_doc]} =
        Enum.split_while(rest, fn {_, l} -> !(l =~ @close) end)

      %{"indent" => indent} = Regex.named_captures(@close, close)
      docs(after_doc, attribute_lines, [{body, String.length(indent)} | acc])
    else
      docs(rest, attribute_lines, acc)
    end
  end

  # The lines of the doc attributes in the code, which leaves out a doc that
  # only appears inside a string.
  defp attribute_line({:@, meta, [{attribute, _, [_doc]}]} = ast, lines)
       when attribute in @doc_attributes,
       do: {ast, MapSet.put(lines, meta[:line])}

  defp attribute_line(ast, lines), do: {ast, lines}

  defp issues({body, base}) do
    state = %{blank?: true, fenced?: false, code_column: base + 4, issues: []}

    %{issues: issues} =
      Enum.reduce(body, state, fn {line_no, line}, state -> line(state, line_no, line, base) end)

    Enum.reverse(issues)
  end

  defp line(state, line_no, line, base) do
    indent = indentation(line)

    cond do
      String.trim(line) == "" ->
        %{state | blank?: true}

      line =~ @fence ->
        fence(state, line_no, line)

      state.fenced? ->
        state

      state.blank? && indent >= state.code_column ->
        %{state | issues: [{line_no, :indented} | state.issues], blank?: false}

      true ->
        %{state | code_column: code_column(state, line, indent, base), blank?: false}
    end
  end

  defp fence(%{fenced?: false} = state, line_no, line) do
    issues = if line =~ @bare_fence, do: [{line_no, :language} | state.issues], else: state.issues
    %{state | fenced?: true, blank?: false, issues: issues}
  end

  defp fence(state, _line_no, _line), do: %{state | fenced?: false, blank?: false}

  # Code after a blank line starts 4 columns past the text it belongs to, which
  # is the doc itself or the list item it sits in. A paragraph at the doc's own
  # indentation ends a list.
  defp code_column(state, line, indent, base) do
    case Regex.run(@list_item, line) do
      [marker | _] -> String.length(marker) + 4
      nil when indent == base -> base + 4
      nil -> state.code_column
    end
  end

  defp indentation(line), do: String.length(line) - String.length(String.trim_leading(line))

  defp issue(context, {line_no, :indented}) do
    format_issue(context,
      message: "Put code in a doc in a fenced block that names its language, such as ```elixir.",
      line_no: line_no
    )
  end

  defp issue(context, {line_no, :language}) do
    format_issue(context,
      message: "Name the language of a fenced block, such as ```elixir.",
      line_no: line_no
    )
  end
end
