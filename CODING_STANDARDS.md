# Coding standards

Every change to Ltix follows these standards, and every review checks against them. The checks in `credo/` enforce the mechanical rules on each `mix precommit`, so this file has the rules that take judgment.

## Reviewing

- A finding is serious when it hurts a real person doing a real task, such as an application that gets a wrong result or a reader who can't find an option. Report every other finding as a papercut, and keep papercuts together at the end.
- Propose a change only when you can show it's better. A finding needs a concrete replacement.
- A rule in this file wins over a general code smell. The [Shape](#shape) rules on concepts that look alike and on repeated small functions override the usual advice about duplicated code and repeated switches.

## Code

### Names

- Use the terms in [GLOSSARY.md](GLOSSARY.md). A new noun in the public API, the docs, or an error message matches a glossary term, or the change adds it to the glossary.
- Spell names out (`authentication`, `administrator`) and use plain CRUD verbs (`create`, `list`, `delete`).
- Name a parameter that passes on another library's options after them, such as `req_options` or `zoi_options`. A parameter named `opts` holds the function's own options.
- Give an internal function a plain name and `@doc false`. Double underscores mark a function that `use` or a macro defines or calls.
- Name a function for everything it does. A `get_`, `fetch_`, or `list_` function has no side effects.

### Shape

- Give each concept the shape its own requirements call for. Two concepts that look alike keep separate mechanics when their requirements differ.
- Extract logic that several modules repeat into one function they all call. Keep macros to a minimum. Several modules that each define the same small function, such as `add_property/2`, read better than one macro that generates them.
- Give each module one job. Split a module that does several unrelated jobs, and keep dependencies between modules pointing one way.
- Inline a module that has one function into the module that uses it.
- Take an external dependency, such as Req options or the storage adapter, as an option, so a test can replace it. Give each platform operation its own function, such as `list_members` or `post_score`, so its stub returns one shape.
- Callers read a library struct with dot syntax or a named function, such as `launch.claims.context` or `Ltix.Launch.get_endpoint/2`.

### Errors

- Raise `ArgumentError` for an unknown or invalid option. Return `{:error, exception}` with an `Ltix.Errors` exception for everything else that can fail.
- An error is a module under its class, `Ltix.Errors.Invalid`, `Ltix.Errors.Security`, or `Ltix.Errors.Unknown`, that calls `use Ltix.Errors` with its fields and class.
- Pass every error on to the caller. Code that turns `{:error, _}` into `:ok` or a default loses the reason.
- Give the functions of a module one return convention. Functions that can fail return `{:ok, value}` or `{:error, exception}`, and their bang variants return the value or raise.
- A `with` whose clauses can fail with something other than `{:error, _}` has an `else` that turns it into one.
- Rescue the specific exceptions a call raises.

### Security

- Compare secrets, such as the state, with `:crypto.hash_equals/2`.
- Generate keys and secrets when the code or test runs. Source files have no secret in them.
- Build a URL with `URI` functions. Check a URL a platform sends before Ltix requests it.
- Validate input where it enters Ltix, at each public function.

### Declared claims and types

Object claims in `lib/ltix/claims/` and other types, such as line items and members, build their structs with `Ltix.Type`.

1. An object claim passes its fields to `use Ltix.Claim` as `fields:`, a keyword list of Zoi schemas. `use` builds the struct, its `t` type, and its enforced keys with `Ltix.Type`, and parses the claim with `Ltix.Type.from_json/3`.
2. A scalar claim implements `parse/2`, usually with `Zoi.parse/2` over a Zoi schema.
3. Another type writes `use Ltix.Provider, hook: [Ltix.Property]` and `use Ltix.Type, fields: [...]`. The default `resolve/1` reports its property conflicts.
4. Every property of a type, including in test plugins, declares a `name:` in `use`.
5. A field with another JSON name has `json_key:` in its schema's metadata.

### Zoi

- Put `Zoi.default/2` after a schema's refinements. Refinements and transforms run in order, so a default before them hides their errors.
- A refinement given as an MFA is called as `fun(value, opts)`, so the function takes two arguments.
- A schema in a module attribute uses the MFA form of a refinement. Anonymous functions can't be stored there.
- `Zoi.keyword/2` drops unrecognized keys by default. Pass `unrecognized_keys: :error` to reject them, or use `Zoi.keyword(Zoi.any())` for options passed on unchanged.
- Use the built-in refinements, such as `Zoi.min/2` and `Zoi.positive/1`, when one fits.

### Comments

- A comment says why, in Ltix's own terms. Point to the spec or an RFC when they're the reason, and leave other libraries' internals out.
- A spec reference goes in a comment next to the code that implements it, as an inline link to the section. Each cited section gets its own link.

### Spec references

Always link spec annotations to the relevant section of the online spec. Label each one the way the linked page shows the section.

Pages on standards.1edtech.org show section titles. Cite them by title, as the page writes it.

`[Core, LTI Deployment ID claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#lti-deployment-id-claim)`

The Security Framework, on imsglobal.org, shows section numbers. Cite it by number.

`[Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)`

| Label | Base URL |
|---|---|
| Core | `https://standards.1edtech.org/lti/specifications/core/lti-spec` |
| AGS | `https://standards.1edtech.org/lti/specifications/services/assignments_grades/assignment-grade-services-spec` |
| DL | `https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec` |
| NRPS | `https://standards.1edtech.org/lti/specifications/services/names_roles/names-role-provisioning-spec` |
| Cert | `https://standards.1edtech.org/lti/specifications/guides/conformance/conformance-guide` |
| Sec | `https://www.imsglobal.org/spec/security/v1p0/` |

Take each anchor from the live page. The local copies in `specs/` are for reading.

## Documentation

Write for an intermediate to experienced Elixir developer with passing EdTech experience. They know LTI as what a platform such as Canvas needs to show their tool, and they haven't read the spec. Use the domain's own words, such as registration, deployment, and signing key, and explain what the spec would have told them.

### Module docs

- Open with one sentence, under about 120 characters, that says what the module is or does for the reader. ExDoc shows it as the summary.
- Describe what the reader can do with the module. What `use` generates, which behaviours a module ends up with, and the steps inside a function are implementation details.
- Show an example when it shows this module's API in a way the prose can't. A module that readers name in one line, such as a launch phase, has no example.
- A module readers never call has `@moduledoc false`.
- Put spec links in a moduledoc only when the spec matters to the reader, as it does for `Ltix.StorageAdapter`.

### Function docs

- Every public function in a module readers call has a `@doc`.
- Open with one sentence in the active voice that says what the function does for the caller. Describe the return value in the opening paragraphs.
- A bang variant's doc is "Same as `fetch/2` but raises on error."
- Each function lists its own options in `## Options`, generated with `Zoi.describe/1` from the schema that validates them.
- Link to the [Error Handling](guides/error-handling.md) guide for the errors a function returns. List only the errors a caller acts on, such as the Deep Linking settings checks on `Ltix.DeepLinking.build_response/3`.
- Write a caveat into the paragraph it belongs to.

### Doctests

- Add a doctest when its output teaches the reader something. A one-line function whose doc already says what it returns needs none.
- Show the value an expression returns.
- Put code in a fenced block that names its language, such as ```elixir. Show code with side effects, such as an HTTP request, without `iex>`.
- Run a module's doctests from its test file with `doctest`.

### Guides

- Give a guide an H1 title and a one-to-three-sentence opening that says what the reader will be able to do.
- Show complete, runnable code that builds on the code before it, with its output and its error cases.
- End with a "Next steps" section that links to related guides and modules.

### Prose

These rules apply to every word a person reads, including docs, comments, error messages, and commit messages.

- Use periods and commas. Leave em dashes, colons, and semicolons out of sentences.
- Start with the point. A section opens with its content and ends when the content does. Openers such as "Here's the thing" and "In this section", closers such as "In summary", and paragraphs that restate the section above them all go.
- Write in the active voice, with the actor as the subject, such as you, the platform, or Ltix. Say what code does with a literal verb, such as has, returns, includes, or calls. A thing doing a person's verb, such as "the launch knows", hides the actor.
- Write "is" when you mean it. "Serves as", "stands as", and "represents" mean "is".
- State what's true, without a contrast clause such as "rather than" or "instead of". Leave out the "not X, but Y" reveal and the countdown of things something isn't.
- Answer only the claims a reader would make. A sentence that denies something nobody said, such as "This doesn't mean Ltix stores your keys", raises the doubt it denies.
- Name the specific thing. A sentence such as "The implications are significant" names nothing. Write "every", "always", or "never" only when the code guarantees it.
- Explain with the real code and behavior. A "Think of it as" analogy, a question the text asks and then answers, and "Let's break this down" treat the reader as a beginner.
- End a sentence when its fact ends. A trailing phrase such as "making integration seamless" adds a claim nobody can check.
- Use plain words. Write "use" for leverage, utilize, and harness, and leave out robust, seamless, streamline, ecosystem, landscape, and delve. Cut adverbs that only add emphasis, such as really, just, simply, actually, fundamentally, and quietly.
- State each point once, in the place a reader looks for it. Use a metaphor once, if at all.
- Vary sentence length and openings. A run of short fragments for emphasis, the same opening three times in a row, and a "What" or "How" lead-in such as "What makes this hard is" read as generated. Give a list as many items as the facts have.
- Start each list item with its content. Bold lead-ins belong to definition lists, such as the glossary.
- Type straight quotes and `->`. Leave out smart quotes and Unicode arrows.
- Use American spellings and fully spelled words.
- Start headings and the opening sentence of a doc with a word other than "The". Write headings in sentence case, except a guide's H1 title.
- Put code names, option keys, atoms, and file paths in backticks.
- Write each Markdown paragraph on one line. Wrap comments and docs in code files.

### Usage rules and shipped skills

`usage-rules.md`, `usage-rules/`, and `usage-rules/skills/` are for agents that help applications use Ltix.

- State a library-wide fact, such as telemetry or error status codes, once in `usage-rules.md`. Each sub-file covers its own topic.
- An example tests the application's own code. A storage adapter test calls the adapter's callbacks and checks its protocol implementations, and leaves the OIDC flow to Ltix.
- An example sets up its data in `setup` and uses the application's naming conventions.
- A skill tells the agent to ask the user with its question tools when it needs a decision.

## Tests

- Test Ltix's behavior through its public entry points, such as `Ltix.handle_login/3`, `Ltix.handle_callback/3`, and the service functions. A test reads like a specification of what a caller can do, and it keeps passing through a refactor that doesn't change behavior. Test only Ltix's own code.
- Name a test for the behavior it shows, such as "rejects a launch whose nonce was already used".
- Check a result through the public API, such as the value a call returns or a later call that reads it back. Private functions and internal state stay out of tests.
- Stub only at the system boundary, which is the platform's HTTP endpoints (`Ltix.Test` stubs), the storage adapter (`Ltix.Test.StorageAdapter`), and the clock. Ltix's own modules run for real, and a test asserts on the results a call returns.
- Take each expected value from an independent source, such as a literal, a worked example, or the spec. An expected value computed the way the code computes it passes by construction.
- Assert on the exact value or struct. A test that can't fail, or that checks a dependency's behavior, tests nothing of Ltix's. A test helper may use a dependency to build its data.
- Each test shows one behavior, and every test asserts something. Delete a skipped, commented-out, or empty test.
- Cover each clause of a public function, through the entry point that reaches it.
- Run tests async. A test that needs a plugin passes it with `plugins:`.
- Leave the application environment alone in tests. When code reads configuration, test it with keys no other test uses.
- Set up each test's data in `setup`. Move setup that several tests repeat into a shared helper.
