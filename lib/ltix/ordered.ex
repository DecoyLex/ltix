defmodule Ltix.Ordered do
  @moduledoc """
  A behaviour for steps that declare their order.

  The `use` that makes a module a step, such as `use Ltix.Login`, declares
  this behaviour. A step orders itself against other steps with
  `c:before?/1` and `c:after?/1`, which default to `false`. Order login and
  launch steps against the phases that `Ltix.Login` and `Ltix.Launch` list,
  such as `Ltix.Login.RegistrationFound`. Client assertions and Deep Linking
  responses have no phases. A plugin can also order the steps it adds,
  including anonymous steps, as
  [Order the steps a plugin adds](#module-order-the-steps-a-plugin-adds) shows.

  ```elixir
  defmodule MyApp.LoginTenant do
    use Ltix.Login

    @impl Ltix.Step
    def call(login, _opts), do: {:ok, login}

    @impl Ltix.Ordered
    def after?(Ltix.Login.RegistrationFound), do: true
    def after?(_module), do: false
  end
  ```

  ## Order

    * Step `A` runs before step `B` when `A.before?(B)` or `B.after?(A)` is
      `true`.
    * When `A` and `B` each declare that they run first, neither order applies.
    * Steps in a cycle of declared orders run in plugin order. Every other
      declared order still applies.
    * An order against a module that isn't running has no effect.
    * Of the steps whose declared orders let them run next, the first in
      [plugin order](`m:Ltix.PluginSet#module-resolution`) runs.

  A step can rely only on its orders. Its place among steps it has no order
  against can change when plugins change. To run between two
  phases, order the step after the first and before the second. To run after
  every other step, return `true` from `c:after?/1` for every module. To run
  before every other step, return `true` from `c:before?/1` for every module.

  Each time a plugin adds a step, it's ordered on its own. A step added twice
  runs twice.

  ## Order the steps a plugin adds

  The `run_after/3` and `run_before/3` functions of `Ltix.Login` and
  `Ltix.Launch` call a function with the plugin, and order each login or launch
  step the function adds after or before a module. An anonymous step has no
  `c:before?/1` or `c:after?/1`, so this is how a plugin orders one.

  ```elixir
  Ltix.Plugin.new(name: "My Library")
  |> Ltix.Login.run_after(Ltix.Login.RegistrationFound, fn plugin ->
    plugin
    |> Ltix.Login.add_step(&MyLibrary.check_tenant/1)
    |> Ltix.Plugin.add(MyLibrary.AuditLogin)
  end)
  ```

    * The order applies along with the orders a step module declares.
    * The calls nest. A `run_before/3` inside a `run_after/3` places steps
      between two modules.
    * Resolution fails with `Ltix.Errors.Unknown.InvalidPluginSet` when these
      calls order a step both before and after another, or when their order
      is part of a cycle.

  No step's `c:before?/1` or `c:after?/1` receives an anonymous step, so a step
  can't order itself against one.
  """

  @doc """
  Returns `true` to run this step before `module`.
  """
  @callback before?(module()) :: boolean()

  @doc """
  Returns `true` to run this step after `module`.
  """
  @callback after?(module()) :: boolean()

  alias Ltix.Plugin
  alias Ltix.PluginSet.Conflict
  alias Ltix.PluginSet.Entry
  alias Ltix.Provider

  @doc """
  Calls `fun` with a plugin, and orders each step of `provider` that `fun`
  adds after `module`.

  A provider whose `:hook` includes `Ltix.Ordered` calls it from a function of
  its own, such as `Ltix.Login.run_after/3`.

  ```elixir
  def run_after(plugin, module, fun),
    do: Ltix.Ordered.run_after(plugin, __MODULE__, module, fun)
  ```

  Raises `ArgumentError` when `fun` doesn't return the plugin it receives with
  only steps of `provider` added.

  ## Examples

  ```elixir
  iex> check_tenant = fn login -> {:ok, login} end
  iex> Ltix.Ordered.run_after(
  ...>   Ltix.Plugin.new(),
  ...>   Ltix.Login,
  ...>   Ltix.Login.RegistrationFound,
  ...>   &Ltix.Login.add_step(&1, check_tenant)
  ...> )
  %Ltix.Plugin{
    entries: [
      %Ltix.PluginSet.Entry{
        module: Ltix.Step,
        opts: [to: Ltix.Login, call: check_tenant],
        orders: [after: Ltix.Login.RegistrationFound]
      }
    ]
  }
  ```
  """
  @spec run_after(Plugin.t(), module(), module(), (Plugin.t() -> Plugin.t())) :: Plugin.t()
  def run_after(plugin, provider, module, fun),
    do: run_ordered(plugin, provider, {:after, module}, fun)

  @doc """
  Calls `fun` with a plugin, and orders each step of `provider` that `fun`
  adds before `module`.

  Works like `run_after/4`.

  ## Examples

  ```elixir
  iex> check_tenant = fn login -> {:ok, login} end
  iex> Ltix.Ordered.run_before(
  ...>   Ltix.Plugin.new(),
  ...>   Ltix.Login,
  ...>   Ltix.Login.RegistrationFound,
  ...>   &Ltix.Login.add_step(&1, check_tenant)
  ...> )
  %Ltix.Plugin{
    entries: [
      %Ltix.PluginSet.Entry{
        module: Ltix.Step,
        opts: [to: Ltix.Login, call: check_tenant],
        orders: [before: Ltix.Login.RegistrationFound]
      }
    ]
  }
  ```
  """
  @spec run_before(Plugin.t(), module(), module(), (Plugin.t() -> Plugin.t())) :: Plugin.t()
  def run_before(plugin, provider, module, fun),
    do: run_ordered(plugin, provider, {:before, module}, fun)

  defp run_ordered(%Plugin{} = plugin, provider, {_placement, module} = order, fun) do
    check_run!(provider, module, fun)
    added = added!(plugin, fun.(plugin), provider)
    %{plugin | entries: plugin.entries ++ Enum.map(added, &%{&1 | orders: &1.orders ++ [order]})}
  end

  defp check_run!(provider, module, fun) do
    unless Provider.hook?(provider, __MODULE__) do
      raise ArgumentError,
            "#{inspect(provider)} doesn't order its steps. Its `use Ltix.Provider` must include Ltix.Ordered in `:hook`."
    end

    unless is_atom(module) && module != Ltix.Step do
      raise ArgumentError,
            "run_after and run_before order steps against a step module, such as a phase, got #{inspect(module)}"
    end

    unless is_function(fun, 1) do
      raise ArgumentError,
            "run_after and run_before need a function of one argument, got #{inspect(fun)}"
    end
  end

  # The entries that the function given to `run_after` or `run_before` added to
  # the plugin.
  defp added!(plugin, changed, provider) do
    added =
      case Plugin.added_entries(plugin, changed) do
        {:ok, added} ->
          added

        :error ->
          raise ArgumentError,
                "the function given to run_after or run_before must return the plugin it receives, " <>
                  "with steps of #{inspect(provider)} added. It returned #{inspect(changed)}."
      end

    for entry <- added, Provider.extended_providers(entry) != [provider] do
      raise ArgumentError,
            "the function given to run_after or run_before can add only steps of " <>
              "#{inspect(provider)}, and it added #{inspect(entry.module)}"
    end

    added
  end

  defmacro __using__(_opts) do
    quote do
      require Ltix.Behaviour

      Ltix.Behaviour.declare_once Ltix.Ordered do
        @doc false
        def before?(_module), do: false

        @doc false
        def after?(_module), do: false

        defoverridable before?: 1, after?: 1
      end
    end
  end

  # Sorts entries by the orders they declare. An entry ordered before another
  # sorts first, unless the two entries order each other both ways. Entries in
  # a cycle stay together, in plugin order. Returns the sorted entries and a
  # conflict for each contradiction or cycle that `run_after` or `run_before`
  # declares.
  @doc false
  @spec sort([Entry.t()]) :: {[Entry.t()], [Conflict.t()]}
  def sort(entries) do
    indexed = Map.new(Enum.with_index(entries), fn {entry, index} -> {index, entry} end)
    {declared, by_functions} = declared(indexed)

    edges =
      for {earlier, later} <- declared, {later, earlier} not in declared, do: {earlier, later}

    groups = components(Map.keys(indexed), edges)
    group_of = for group <- groups, index <- group, into: %{}, do: {index, group}

    group_edges =
      for {earlier, later} <- edges,
          group_of[earlier] != group_of[later],
          uniq: true,
          do: {group_of[earlier], group_of[later]}

    sorted =
      groups
      |> take_ready(group_edges, [])
      |> Enum.flat_map(fn group -> Enum.map(group, &indexed[&1]) end)

    {sorted, conflicts(indexed, groups, declared, by_functions)}
  end

  # The pairs of entry indexes that declare an order, the first running before
  # the second, and the pairs among them that `run_after` or `run_before`
  # declares.
  defp declared(indexed) do
    # No module's callbacks see an anonymous step.
    modules =
      Enum.uniq(
        for {_index, %Entry{module: module} = entry} <- indexed,
            !Entry.anonymous?(entry),
            do: module
      )

    by_modules =
      for first <- modules,
          second <- modules,
          first != second,
          first.before?(second) || second.after?(first),
          into: MapSet.new(),
          do: {first, second}

    by_functions =
      for {earlier, first} <- indexed,
          {later, second} <- indexed,
          earlier != later,
          {:before, second.module} in first.orders || {:after, first.module} in second.orders,
          into: MapSet.new(),
          do: {earlier, later}

    declared =
      for {earlier, first} <- indexed,
          {later, second} <- indexed,
          earlier != later,
          {first.module, second.module} in by_modules || {earlier, later} in by_functions,
          into: MapSet.new(),
          do: {earlier, later}

    {declared, by_functions}
  end

  # A conflict for each pair that `run_after` or `run_before` orders both ways,
  # and each cycle that includes an order from `run_after` or `run_before`.
  defp conflicts(indexed, groups, declared, by_functions) do
    contradictions =
      for {earlier, later} <- by_functions,
          {later, earlier} in declared,
          uniq: true do
        %Conflict{
          parties: Enum.map(Enum.sort([earlier, later]), &indexed[&1]),
          reason: "are ordered both before and after each other"
        }
      end

    cycles =
      for [_, _ | _] = group <- groups,
          Enum.any?(by_functions, fn {earlier, later} -> earlier in group && later in group end) do
        %Conflict{parties: Enum.map(group, &indexed[&1]), reason: "are ordered in a cycle"}
      end

    contradictions ++ cycles
  end

  # The strongly connected components, which are the cycles and the entries
  # in no cycle, each sorted and listed by its first entry.
  defp components(indexes, edges) do
    graph = :digraph.new()

    try do
      Enum.each(indexes, &:digraph.add_vertex(graph, &1))
      Enum.each(edges, fn {earlier, later} -> :digraph.add_edge(graph, earlier, later) end)

      graph
      |> :digraph_utils.strong_components()
      |> Enum.map(&Enum.sort/1)
      |> Enum.sort_by(&hd/1)
    after
      :digraph.delete(graph)
    end
  end

  # The groups form an acyclic graph, so one group is always ready. Ties go to
  # plugin order.
  defp take_ready([], _edges, sorted), do: Enum.reverse(sorted)

  defp take_ready(groups, edges, sorted) do
    ready =
      Enum.find(groups, fn group ->
        !Enum.any?(edges, fn {earlier, later} -> later == group && earlier in groups end)
      end)

    take_ready(List.delete(groups, ready), edges, [ready | sorted])
  end
end
