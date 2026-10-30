defmodule Ltix.Credo.InternalFunctions do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      A double-underscore name marks a function that `use` or a macro defines
      or calls, such as `__ltix_hook__/0`. Give another internal function a
      plain name and `@doc false`.

          @doc false
          def add_entry(plugin, entry), do: ...
      """
    ]

  @typespecs [:spec, :callback, :macrocallback, :type, :typep, :opaque]

  @impl Credo.Check
  def run_on_all_source_files(exec, source_files, params) do
    names = Enum.reduce(source_files, MapSet.new(), &definitions/2)

    source_files
    |> Enum.flat_map(&calls(&1, names, params))
    |> append_issues_and_timings(exec)

    :ok
  end

  # The double-underscore functions a file defines outside `quote`.
  defp definitions(source_file, names) do
    Credo.Code.prewalk(source_file, &collect_definition/2, names)
  end

  defp collect_definition({:quote, _, _}, names), do: {nil, names}

  defp collect_definition({:def, _, [head | _]} = ast, names) do
    name = name(head)
    {ast, if(dunder?(name), do: MapSet.put(names, name), else: names)}
  end

  defp collect_definition(ast, names), do: {ast, names}

  defp calls(source_file, names, params) do
    context = Context.build(source_file, params, __MODULE__, %{names: names})
    Credo.Code.prewalk(source_file, &walk/2, context).issues
  end

  defp walk({:quote, _, _}, context), do: {nil, context}

  defp walk({:@, _, [{attribute, _, _}]}, context) when attribute in @typespecs,
    do: {nil, context}

  defp walk({:def, _, [_head | body]}, context), do: {body, context}
  defp walk({:defp, _, [_head | body]}, context), do: {body, context}

  defp walk({{:., _, [_receiver, name]}, meta, arguments} = ast, context)
       when is_list(arguments),
       do: {ast, check_call(context, name, meta)}

  defp walk({name, meta, arguments} = ast, context) when is_atom(name) and is_list(arguments),
    do: {ast, check_call(context, name, meta)}

  defp walk(ast, context), do: {ast, context}

  defp check_call(context, name, meta) do
    if MapSet.member?(context.names, name) do
      put_issue(
        context,
        format_issue(context,
          message: "Name `#{name}` without double underscores, since only Ltix code calls it.",
          trigger: Atom.to_string(name),
          line_no: meta[:line]
        )
      )
    else
      context
    end
  end

  defp name({:when, _, [head | _]}), do: name(head)
  defp name({name, _, _}) when is_atom(name), do: name
  defp name(_head), do: nil

  defp dunder?(name) when is_atom(name) and not is_nil(name) do
    string = Atom.to_string(name)
    String.starts_with?(string, "__") && String.ends_with?(string, "__")
  end

  defp dunder?(_name), do: false
end
