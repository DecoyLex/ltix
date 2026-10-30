defmodule Ltix.Credo.OptionsDocs do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      A public function that takes options lists them in its own `## Options`
      section, generated from the schema that validates them.

          @doc \"\"\"
          Fetches the members.

          ## Options

          \#{Zoi.describe(@list_members_schema)}
          \"\"\"
          def list_members(client, opts \\\\ [])

      Name a parameter that passes on another library's options after them,
      such as `req_options`.
      """
    ]

  @option_names [:opts, :options]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, context).issues
  end

  defp walk({:defmodule, _, [_alias, [do: body]]} = ast, context) do
    statements = statements(body)

    state = %{
      context: context,
      defined: defined(statements),
      doc: nil,
      hidden?: false,
      impl?: false,
      seen: MapSet.new()
    }

    {ast, Enum.reduce(statements, state, &statement/2).context}
  end

  defp walk(ast, context), do: {ast, context}

  defp statements({:__block__, _, statements}), do: statements
  defp statements(statement), do: [statement]

  defp defined(statements) do
    for {:def, _, [head | _]} <- statements, into: MapSet.new() do
      {name, arguments} = signature(head)
      {Atom.to_string(name), length(arguments)}
    end
  end

  defp statement({:@, _, [{:moduledoc, _, [false]}]}, state), do: %{state | hidden?: true}
  defp statement({:@, _, [{:doc, _, [doc]}]}, state), do: %{state | doc: doc}
  defp statement({:@, _, [{:impl, _, _}]}, state), do: %{state | impl?: true}

  defp statement({:def, meta, [head | _]}, state) do
    {name, arguments} = signature(head)
    key = {name, length(arguments)}

    context =
      if MapSet.member?(state.seen, key) || !undocumented_options?(name, arguments, state),
        do: state.context,
        else: add_issue(state.context, name, meta)

    %{state | context: context, doc: nil, impl?: false, seen: MapSet.put(state.seen, key)}
  end

  defp statement(_statement, state), do: state

  defp signature({:when, _, [head | _]}), do: signature(head)
  defp signature({name, _, arguments}) when is_list(arguments), do: {name, arguments}
  defp signature({name, _, _context}), do: {name, []}

  defp undocumented_options?(name, arguments, state) do
    Enum.any?(arguments, &options?/1) && !state.hidden? && !state.impl? && state.doc != false &&
      !bang_variant?(name, arguments, state) && !generated_options?(state.doc)
  end

  # A bang variant points to the function it wraps, which lists the options.
  defp bang_variant?(name, arguments, state) do
    string = Atom.to_string(name)

    String.ends_with?(string, "!") &&
      MapSet.member?(state.defined, {String.trim_trailing(string, "!"), length(arguments)})
  end

  defp options?({:\\, _, [argument, _default]}), do: options?(argument)
  defp options?({name, _, context}) when is_atom(context), do: name in @option_names
  defp options?(_argument), do: false

  defp generated_options?(doc) do
    {_doc, found} = Macro.prewalk(doc, MapSet.new(), &find_options/2)
    MapSet.equal?(found, MapSet.new([:heading, :describe]))
  end

  defp find_options(text, found) when is_binary(text) do
    {text, if(text =~ "## Options", do: MapSet.put(found, :heading), else: found)}
  end

  defp find_options({{:., _, [{:__aliases__, _, [:Zoi]}, :describe]}, _, _} = ast, found),
    do: {ast, MapSet.put(found, :describe)}

  defp find_options(ast, found), do: {ast, found}

  defp add_issue(context, name, meta) do
    put_issue(
      context,
      format_issue(context,
        message: "List the options of `#{name}` in its docs with `Zoi.describe/1`.",
        trigger: Atom.to_string(name),
        line_no: meta[:line]
      )
    )
  end
end
