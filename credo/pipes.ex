defmodule Ltix.Credo.Pipes do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      A pipeline starts with a raw value and has at least two calls. Write one
      call as a function call.

          list
          |> Enum.sort()
          |> Enum.take(5)

      Builder chains are the exception. A Zoi chain, a Req call, and an Ltix
      builder chain start with a call and can have one. An Ltix builder chain
      (`Ltix.Plugin` and `Ltix.Validator`) always pipes from `new(...)`.

          Ltix.Plugin.new(name: "Blocklist")
          |> Ltix.Plugin.add(Blocklist.Login)
      """
    ]

  # Forms that build a value, which a pipeline may start with.
  @value_forms [:%{}, :{}, :<<>>, :%, :@, :__MODULE__, :&, :fn, :.., :..//]

  # Modules whose builder chains start with a call.
  @builder_modules [:Zoi, :Req]

  # Ltix builders, whose chains start with `new(...)`.
  @ltix_builders [:Plugin, :Validator]

  # The `Ltix.Validator` functions a message type calls without the module.
  @validator_functions [:required, :optional, :override, :defaults]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, context).issues
  end

  # Checks a whole pipeline once, then walks only its start and arguments, so
  # its inner `|>` aren't checked as pipelines of their own.
  defp walk({:|>, meta, _} = ast, context) do
    {start, calls} = flatten(ast, [])
    children = [start | Enum.flat_map(calls, &arguments/1)]
    {{:__block__, [], children}, check(context, start, calls, meta)}
  end

  defp walk({function, meta, [first | _]} = ast, context) do
    if wraps_new?(function, first) do
      {ast, add_issue(context, meta, "Pipe an Ltix builder chain from `new(...)`.", "new")}
    else
      {ast, context}
    end
  end

  defp walk(ast, context), do: {ast, context}

  defp flatten({:|>, _, [left, call]}, calls), do: flatten(left, [call | calls])
  defp flatten(start, calls), do: {start, calls}

  defp arguments({_, _, arguments}) when is_list(arguments), do: arguments
  defp arguments(_call), do: []

  defp check(context, start, calls, meta) do
    cond do
      builder_start?(start) || Enum.all?(calls, &zoi?/1) ->
        context

      call?(start) ->
        add_issue(context, meta, "Start a pipeline with a raw value.")

      length(calls) == 1 ->
        add_issue(context, meta, "Write a pipeline with one call as a function call.")

      true ->
        context
    end
  end

  defp wraps_new?({:., _, [_, _]}, first), do: ltix_new?(first)

  defp wraps_new?(function, {:new, _, arguments}) when is_list(arguments),
    do: function in @validator_functions

  defp wraps_new?(function, first) when is_atom(function) and function != :__block__,
    do: ltix_new?(first)

  defp wraps_new?(_function, _first), do: false

  defp builder_start?({{:., _, [{:__aliases__, _, [module]}, _function]}, _, _})
       when module in @builder_modules,
       do: true

  # A message type's validator calls `new/1` without the module.
  defp builder_start?({:new, _, arguments}), do: is_list(arguments)
  defp builder_start?(start), do: ltix_new?(start)

  defp zoi?({{:., _, [{:__aliases__, _, [:Zoi]}, _function]}, _, _}), do: true
  defp zoi?(_call), do: false

  defp ltix_new?({{:., _, [{:__aliases__, _, segments}, :new]}, _, _}),
    do: List.last(segments) in @ltix_builders

  defp ltix_new?(_ast), do: false

  # `map.field` has no parentheses, so it reads a value.
  defp call?({{:., _, [_, _]}, meta, _arguments}), do: !meta[:no_parens]

  defp call?({name, _, arguments}) when is_atom(name) and is_list(arguments) do
    name not in @value_forms && !sigil?(name) && !Macro.operator?(name, length(arguments))
  end

  defp call?(_value), do: false

  defp sigil?(name), do: String.starts_with?(Atom.to_string(name), "sigil_")

  defp add_issue(context, meta, message, trigger \\ "|>") do
    put_issue(
      context,
      format_issue(context, message: message, trigger: trigger, line_no: meta[:line])
    )
  end
end
