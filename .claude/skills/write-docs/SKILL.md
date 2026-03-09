---
name: write-docs
description: Write or review Elixir documentation following the project's style guide. Use when writing @moduledoc, @doc, guides, or reviewing existing docs for quality. Invoke with "/write-docs" or when the user asks to write, improve, or review documentation.
version: 0.1.0
---

# Write Documentation (`/write-docs`)

Write or review documentation for $ARGUMENTS, following the conventions below.

Distilled from studying Phoenix, Ecto, Plug, Req, Ash, Oban, Tesla, Jason,
NimbleOptions, and Elixir's official writing-documentation guide.

## Core principle

Documentation is a **contract with the library consumer**. It tells them
*what* things do and *how to use* them. Code tells them *how* it works.
Comments tell them *why*.

---

## @moduledoc

### Opening sentence

Lead with one plain-English sentence that tells the reader what the module
*is* or *does for them*. This sentence becomes the summary in ExDoc and
`mix docs`. Keep it under ~120 characters.

**Patterns to follow:**
- Data structs: "A [thing] representing [what]." or "[Noun] for [purpose]."
- Behaviours: "Defines callbacks for [purpose]."
- Facades: "[Verb]s [things] for [purpose]."
- Services: "Query/Fetch/Manage [thing] from [source]."

**Anti-patterns:**
- Starting with "This module..." (waste of words, reader knows it's a module)
- Starting with "The" (project convention: never start headings with "The")
- Implementation language: "A pure function that..." / "Delegates to..."

**Good openers from top libraries:**

| Library | Opening |
|---|---|
| Plug.Conn | "The Plug connection." |
| Ecto.Changeset | "Changesets allow filtering, type casting, validation, and constraints when manipulating structs." |
| Req | "Req is a batteries-included HTTP client for Elixir." |
| Ash | "The primary interface to call actions and interact with resources." |

### Body structure

After the opening, use `##` sections. Common sections in order:

1. **Prose explanation** (unlabeled, right after the opening)
2. `## Examples` or `## Usage` (show the happy path first)
3. `## Fields` / `## Options` / `## Configuration`
4. `## Sections for major concepts`

### Component lists

For facade modules that tie together multiple submodules, list them early:

```elixir
@moduledoc """
Ltix handles the LTI 1.3 OIDC launch flow. It is built around 4 components:

  * `Ltix.Registration` - what the tool knows about a platform
  * `Ltix.StorageAdapter` - behaviour your app implements
  * `Ltix.LaunchContext` - the validated output of a launch
  * `Ltix.LaunchClaims` - structured data from the ID Token
"""
```

### What NOT to put in @moduledoc

- Spec citations (put in code comments next to implementing code)
- Implementation details ("uses GenServer", "delegates to X", "pure function")
- Internal pipeline steps or algorithm descriptions

---

## @doc (function documentation)

### Opening line

One sentence, active voice, present tense. Describe what the function does
*for the caller*, not how it works internally.

**Good:**
- "Assigns a value to a key in the connection."
- "Fetches a single result from the query."
- "Acquire an OAuth token for the memberships service."

**Bad:**
- "This function assigns..." (redundant preamble)
- "Calls the internal assign pipeline to..." (implementation detail)
- "A pure function that returns..." (implementation detail)

### Parameters

For simple functions, parameters are self-evident from the typespec and
argument names. Don't repeat what's obvious. For complex functions,
document parameters inline or under a short paragraph:

```elixir
@doc """
Inserts a struct defined via `Ecto.Schema` or a changeset.

When given a struct, it is converted to a changeset with all non-nil
fields as changes. When given a changeset, all changes in the changeset
are sent to the database.
"""
```

When the compiler infers a bad argument name from pattern matching,
declare a function head to fix it:

```elixir
def size(map_with_size)
def size(%{size: size}), do: size
```

### Options

Use `## Options` with a bullet list. NimbleOptions docs generate
automatically; for hand-written options:

```elixir
@doc """
...

## Options

  * `:role` - filter by role. Accepts a role atom (e.g., `:learner`),
    URI string, or `%Role{}` struct.
  * `:per_page` - page size hint. The platform may return more or fewer.
  * `:max_members` - safety limit for eager fetch (default: `10_000`).
    Set to `:infinity` to disable.
"""
```

**Style rules for options:**
- `:option_name` in backtick-code
- Lowercase start after the dash
- Default values noted inline: `(default: \`value\`)`
- For options that accept multiple forms, use indented sub-bullets:

```
  * `:auth` - sets request authentication.
    - `{:basic, userinfo}` - Basic HTTP authentication
    - `{:bearer, token}` - Bearer authentication
```

### Return values

Document return types in the opening paragraphs, not as a separate section:

```elixir
@doc """
Fetches a single result from the query.

Returns `nil` if no result is found. Raises if more than one entry.
"""
```

### Bang variants

Keep bang docs minimal. Reference the non-bang variant:

```elixir
@doc """
Same as `authenticate/2` but raises on error.
"""
```

### Examples / Doctests

- Use `## Examples` heading
- Show the simplest usage first, then variations
- Avoid assertions in doctests (they clutter docs for the end user).
  Show inputs and outputs directly:

```elixir
## Examples

    iex> conn = assign(conn, :hello, :world)
    iex> conn.assigns[:hello]
    :world
```

- For functions with side effects or external dependencies, use plain
  code blocks without `iex>`:

```elixir
## Examples

    {:ok, client} = MembershipsService.authenticate(context)
    {:ok, roster} = MembershipsService.get_members(client)
```

- **When NOT to use doctests**: code with side effects (IO, file writes),
  code that defines persistent modules, non-deterministic results.
- Multiline expressions use `...>` continuation prefix
- Separate doctests with blank lines to isolate variable scope

### Cross-references (ExDoc auto-linking)

- Modules: `` `MyModule` `` or `` `m:MyModule` ``
- Functions: `` `function/arity` `` (local) or `` `Module.function/arity` ``
- Callbacks: `` `c:callback/arity` ``
- Types: `` `t:type/arity` ``
- Erlang modules: `` `m::erlang_mod` ``
- Custom link text: `` [text](`Module.function/1`) ``
- Guides: `[Guide Title](guide-name.md)`
- Anchors: `` `m:Module#module-section-name` ``

### Important caveats

Call out important behavior inline, not in a separate "Notes" section:

```elixir
@doc """
Sends a response with the given status and body.

This function does not halt the connection, so if subsequent plugs
try to send another response, it will error out. Use `halt/1` after
this function if you want to halt the plug pipeline.
"""
```

---

## Guides

### When to write a guide vs. moduledoc

- **Guide**: Teaches a concept, walks through a workflow, explains *why*.
- **Moduledoc**: Documents an API. Reader is looking up how to call something.

### Structure

1. **H1 title** (no "The" prefix). Short, descriptive.
2. **Opening paragraph**: 1-3 sentences. What the guide covers and what
   the reader will know by the end.
3. **H2 sections**: Major steps or concepts.
4. **H3 subsections**: Details within a section.
5. **Next steps**: End with links to related guides and module docs.

### Guide patterns

| Pattern | When to use | Example |
|---|---|---|
| **Signpost** | Orientation, landing pages | Phoenix overview |
| **Linear tutorial** | Teaching a workflow | Ecto Getting Started |
| **Feature showcase** | Introducing a library | Req README |
| **Task guide** | Procedural how-to | Oban installation |

### Code examples in guides

- Show real, runnable code (not pseudocode)
- Include file path comments when context matters: `# lib/my_app_web/router.ex`
- Show complete examples that can be copy-pasted
- Progress from simple to complex
- **Show both input and output** so the reader knows what to expect
- **Show error cases alongside success**
- **Build progressively**: reuse variables from earlier sections

### Tables

Use tables for comparisons, quick reference, and callback summaries:

```markdown
| Callback | Called during | Purpose |
|---|---|---|
| `get_registration/2` | Login initiation | Look up a platform |
```

### Admonitions

Use ExDoc admonitions sparingly for genuinely important warnings:

```markdown
> #### Production {: .warning}
>
> The in-memory Agent is fine for development. In production, store
> nonces in your database with a TTL.
```

Types: `.info`, `.warning`, `.error`, `.tip`, `.neutral`

### Cross-linking

- Link to module docs with backtick syntax: `` `Ltix.LaunchContext` ``
- Link to other guides with relative paths: `[Error Handling](error-handling.md)`
- End each guide with a "Next steps" section listing 3-5 related resources

---

## Metadata

Use `@doc since:` and `@moduledoc since:` to annotate when things were
added to the public API:

```elixir
@doc since: "0.2.0"
```

Use `@doc deprecated:` for soft deprecation (warning in docs, no
compile warning):

```elixir
@doc deprecated: "Use authenticate/2 instead"
```

Use `@doc group:` to group functions in ExDoc sidebar:

```elixir
@doc group: "Query"
def get_members(client, opts \\ [])
```

---

## Internal modules

Use `@moduledoc false` for modules that consumers never interact with
directly. These are implementation details behind a facade. Examples:
parsers, internal helpers, protocol implementations.

Still document functions with `@doc` if the module is complex enough that
*developers on the project* benefit from it, but the moduledoc stays false.

---

## Writing style

### Punctuation
- Prefer periods, commas, colons. Use em dashes and semicolons sparingly.
- One space after periods.

### Headings
- Never start with "The" (project convention)
- Use sentence case: "Getting started", not "Getting Started"
  (Exception: when used as a proper title in guide H1)

### Voice
- Active voice, present tense: "Returns the value" not "The value is returned"
- Second person for guides: "Add this to your router"
- Imperative for instructions: "Store the state in the session"

### Technical terms
- Use backtick-code for: module names, function names, option keys, atoms,
  struct names, file paths
- Don't use backtick-code for: general English words, protocol names used
  conversationally

### Length
- Keep the first paragraph of any @moduledoc or @doc concise. ExDoc uses
  the first line/paragraph as the summary in lists.
- Function docs should typically be 3-15 lines.
- Guide sections should be skimmable. If a section is longer than ~2 screens,
  break it into subsections.

---

## Spec references (ltix-specific)

Spec references belong in **code comments next to the implementing code**,
NOT in user-facing docs. Use the anchor mappings in `spec-anchors.md`.

Format: `# [Core 5.1.2](https://www.imsglobal.org/spec/lti/v1p3/#lti-domain-model)`

Exception: modules where the spec is directly relevant to the library
consumer (e.g., `StorageAdapter`) may include spec refs in `@moduledoc`/`@doc`.

---

## Checklist

Before finalizing documentation, verify:

- [ ] Opening sentence tells the reader what it is/does, not how
- [ ] No spec citations in user-facing docs (code comments instead)
- [ ] No implementation details leaked
- [ ] Doctests present on public functions where reasonable
- [ ] Doctests have no assertions (show input/output directly)
- [ ] Options documented with `:key` - description format
- [ ] Cross-references use correct ExDoc syntax
- [ ] Guides end with "Next steps"
- [ ] No headings start with "The"
- [ ] Internal modules have `@moduledoc false`
- [ ] Bang variants reference their non-bang counterpart
