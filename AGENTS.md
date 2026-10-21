## Commit Messages

This project enforces [Conventional Commits](https://www.conventionalcommits.org/).
Validation is done with [cocogitto](https://docs.cocogitto.io/) (`cog`).

### Format
```
<type>[(scope)][!]: <description>

[optional body]

[optional footer(s)]
```

### Co-Authors
When multiple people contribute to a commit, include co-authors in the footer:
```
Co-authored-by: Name <email@example.com>
```

AI assistants MUST NEVER be listed as co-authors, even if they contributed to the commit message or code. Only the human(s) responsible for the commit may be listed as co-authors.

### Allowed types
`build`, `chore`, `ci`, `docs`, `feat`, `fix`, `improvement`, `perf`, `refactor`, `revert`, `style`, `test`

### Validation
```bash
cog check --from-latest-tag   # check all since last tag
```

## Quality Checks

Always run quality checks before committing. 

```bash
mix precommit
```

Use the `qc` skill for checks on test hygiene

## Pipes

- Don't use a single `|>`. Call the function directly. Zoi builder chains, Ltix builder chains, and Req response piping are exceptions.
- Start pipe chains with a raw value, not a function call. Zoi type constructors, Ltix builder chains, and Req HTTP calls are exceptions.
- Ltix builder chains (`Ltix.Plugin` declarations and `Ltix.Validator`) always pipe from `new(...)`, even for one call, with each call on its own line. Write `Ltix.Plugin.new(name: "Blocklist")` and then `|> Ltix.Plugin.add(Blocklist.Login)`, not `Ltix.Plugin.add(Ltix.Plugin.new(name: "Blocklist"), Blocklist.Login)`.

## Doctests

Include doctests on public functions whenever reasonable. Doctests serve as both documentation and tests.
Avoid assertions in doctests — they muddy things for the end-user. Show inputs and outputs directly.

## Declared Claims and Types

Object claims (in `lib/ltix/claims/`) and other types, such as line items and members, build their structs with `Ltix.Type`.

1. An object claim passes its fields to `use Ltix.Claim` as `fields:`, a keyword list of Zoi schemas. `use` builds the struct, its `t` type, and its enforced keys with `Ltix.Type`, and parses the claim with `Ltix.Type.from_json/3`.
2. A scalar claim implements `parse/2`, usually with `Zoi.parse/2` over a Zoi schema.
3. Another type writes `use Ltix.Provider, hook: [Ltix.Property]` and `use Ltix.Type, fields: [...]`. The default `resolve/1` reports its property conflicts.
4. Every property of a type, including in test plugins, declares a `name:` in `use`.
5. Give a field another JSON name with `json_key:` in its schema's metadata.

## Spec References

Always link spec annotations to the relevant section of the online spec. 

Format: `[Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)`

<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
# Elixir Core Usage Rules

## Pattern Matching
- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling
- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid
- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design
- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures
- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing
- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
# OTP Usage Rules

## GenServer Best Practices
- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication
- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance
- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async
- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
