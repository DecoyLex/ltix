---
name: write-docs
description: Write or review Elixir documentation following the project's standards. Use when writing @moduledoc, @doc, guides, or reviewing existing docs for quality. Invoke with "/write-docs" or when the user asks to write, improve, or review documentation.
version: 0.2.0
---

# Write documentation (`/write-docs`)

Write or review documentation for $ARGUMENTS.

## Steps

1. Read the Documentation section of [CODING_STANDARDS.md](../../../CODING_STANDARDS.md). Done when you can name the reader it describes.
2. For each page, write down what the reader came to do. A moduledoc's reader came to call the module, and a guide's reader came to finish a task.
3. Write or review the page against every rule in the Documentation section. Done when each sentence serves the reader's task and follows every rule.
4. Run `MIX_ENV=dev mix docs`. Done when it prints no warnings.

## ExDoc reference

### Cross-references

- Modules: `` `MyModule` `` or `` `m:MyModule` ``
- Functions: `` `function/arity` `` (local) or `` `Module.function/arity` ``
- Callbacks: `` `c:callback/arity` ``
- Types: `` `t:type/arity` ``
- Erlang modules: `` `m::erlang_mod` ``
- Custom link text: `` [text](`Module.function/1`) ``
- Guides: `[Guide Title](guide-name.md)`
- Anchors: `` `m:Module#module-section-name` ``

### Options

Generate a function's options from the schema that validates them. Give each option a `description:` that starts with a capital letter and ends with a period. `Zoi.describe/1` adds the type and the default.

```elixir
@list_members_schema Zoi.keyword(
                       [
                         per_page:
                           Zoi.integer(description: "A page size hint. The platform may return more or fewer.")
                           |> Zoi.optional()
                       ],
                       unrecognized_keys: :error
                     )

@doc """
Fetches every member of the context.

## Options

#{Zoi.describe(@list_members_schema)}
"""
```

### Admonitions

Use an admonition for a warning the reader can't miss.

```markdown
> #### Production {: .warning}
>
> The in-memory Agent is fine for development. In production, store
> nonces in your database with a TTL.
```

Types: `.info`, `.warning`, `.error`, `.tip`, `.neutral`

### Metadata

- `@doc since: "0.2.0"` for when a function joined the public API
- `@doc deprecated: "Use authenticate/2 instead"` for a soft deprecation
- `@doc group: "Query"` to group functions in the sidebar
