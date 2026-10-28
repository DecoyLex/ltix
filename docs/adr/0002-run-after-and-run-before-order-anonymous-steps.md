# `run_after` and `run_before` order anonymous steps

An anonymous step has no module, so it can't implement `before?/1` and `after?/1`. A plugin orders it with `run_after/3` or `run_before/3` on the step's provider, which orders every step the given function adds.

```elixir
Ltix.Plugin.new(name: "My Library")
|> Ltix.Launch.run_after(Ltix.Launch.ClaimsParsed, fn plugin ->
  plugin
  |> Ltix.Launch.add_step(&MyLibrary.record_tenant/1)
  |> Ltix.Plugin.add(MyLibrary.CheckTenant)
end)
```

Calls to `run_after/3` and `run_before/3` nest, so a `run_before/3` inside a `run_after/3` places steps between two phases. They also order the step modules the given function adds, along with the orders those modules' own `before?/1` and `after?/1` declare. A function given to `run_after/3` or `run_before/3` that adds anything other than its provider's steps raises `ArgumentError`. An order from `run_after/3` or `run_before/3` that contradicts a module's own order, or that forms a cycle, makes resolution fail with a conflict. A prototype showed that a silently dropped order runs the step somewhere its author didn't intend.

Launches end with the `Ltix.Launch.DeploymentFound` phase, so `run_after/3` can place steps after the deployment lookup.

## Considered options

- **`:before` and `:after` options on `add_step`.** `run_after/3` and `run_before/3` order step modules and groups of steps too, and one way to order steps is easier to learn.
- **`after/3` and `before/3`.** `after` is a reserved word in Elixir, so defining the function takes `def unquote(:after)`.
- **`run_last/2`**, for steps that need the deployment. A phase uses the ordering Ltix already has.
