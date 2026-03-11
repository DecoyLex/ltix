---
name: qc
description: This skill should be used when the user says "/qc", "quality check", "check code quality", "run quality checks", or "check formatting and tests". It runs formatting, linting, and test review checks on the current codebase.
version: 0.2.0
---

# Quality Check (`/qc`)

Run all quality checks on the current codebase. Report results concisely — only surface problems, not passing checks.

## Checks to Run

Launch all three checks **in parallel** (single message, multiple tool calls):

### 1. Formatting (Bash)

```bash
mix format --check-formatted
```

If this fails, run `mix format` to fix, then report which files were reformatted.

### 2. Credo (Bash)

```bash
mix credo --strict
```

Report any issues found. Do not auto-fix — just report.

### 3. Test Review (Subagent)

Launch a Task subagent (`subagent_type: "Explore"`) with the following prompt (customized to your modified codebase):

> Review the following test files in the `test/` directory for common test hygiene issues.
> - tests/my_new_tests.exs
> - tests/existing_tests.exs (test c, d, etc.)
>
>Read every test file and check for these problems:
>
> **Tautological tests**: Tests that assert a value equals itself, `assert true`, `assert 1 == 1`, or other assertions that can never fail. Also catch tests where the expected value is derived from the same code path as the actual value.
>
> **Testing dependencies instead of our code**: Tests that verify behavior of third-party libraries (JOSE, Splode, Req, Plug) rather than testing the project's own modules. For example, testing that `JOSE.JWK.generate_key` returns a key is testing JOSE, not our code. Test helpers that use dependencies to set up fixtures are fine — the problem is when the *assertion* tests dependency behavior.
>
> **Missing assertions**: Test bodies that perform operations but never call `assert`, `refute`, `assert_raise`, `assert_receive`, or other ExUnit assertion macros.
>
> **Overly broad assertions**: Using `assert is_map(result)` or `assert is_binary(result)` when more specific structural assertions would be appropriate. For example, asserting `is_map` on a struct when you could assert the struct type.
>
> **Dead tests**: Tests that are `@tag :skip`'d, commented out, or have empty bodies.
>
> For each issue found, report:
> - File path and line number
> - The test name
> - What the issue is
> - A brief suggestion for improvement
>
> If no issues are found, report that all tests look clean.

## 4. Code Review (Subagent)

While the test review is running, launch a second Task subagent to review the modified
code files for general code quality issues (not just tests). Use a similar prompt structure
to the test review, but focus on code quality issues like:

> Review the Elixir codebase under lib/ and test/ for anti-patterns, WATs, and code quality issues. Report every finding with file path, line number, and a brief explanation of why it's problematic.
>
> Focus on the following files/areas of the codebase:
> - lib/my_new_code.ex
> - lib/existing_code.ex (function a, b, etc.)
>
> Categories to check:
>
> 1. Elixir Anti-Patterns
> - Single-pipe (|>) usage (one pipe into a function — just call it directly). Exceptions: Zoi builder chains and Req response piping.
> - Pipe chains that start with a function call instead of a raw value. Exceptions: Zoi type constructors and Req HTTP calls.
> - case/cond/if that could be pattern-matched function heads instead.
> - Nested case or with statements that should be flattened or extracted.
> - with blocks that have a single clause (just use case or pattern match).
> - Bare rescue or overly broad rescue _ without specific exception types.
> - String.to_atom/1 on dynamic input.
> - Enum on large/lazy collections where Stream would be appropriate.
> - Appending to lists with ++ instead of prepending with [h | t].
> - Raw maps where a struct would be more appropriate (repeated known-shape maps).
> - Dead code: unused functions, unreachable clauses, variables prefixed with _ that are actually used.
>
> 2. Error Handling WATs
> - Swallowed errors: {:error, _} -> :ok or similar patterns that discard error information.
> - Inconsistent ok/error tuple usage (some functions return bare values, others tuples, in the same module).
> - raise used for control flow rather than truly exceptional cases.
> - Missing error clauses in with blocks (no else when the non-happy paths aren't all {:error, _}).
>
> 3. Test Quality
> - Tests that assert on dependency behavior rather than the code under test.
> - Overly broad assertions (assert is_map(result) instead of asserting specific fields).
> - Tests with no assertions at all.
> - Tests that rely on global state (Application.put_env/delete_env in async tests).
> - Duplicated test setup that should be extracted.
> - Missing edge case coverage for public functions that handle multiple clause patterns.
>
> 4. Documentation & Naming
> - Public functions missing @doc.
> - Public modules missing @moduledoc.
> - Internal-only modules that are missing @moduledoc false.
> - Misleading function names (e.g., a function named get_* that has side effects).
> - Predicate functions using is_ prefix instead of ? suffix.
>
> 5. Structural Issues
> - Modules doing too many things (God modules).
> - Circular or tangled module dependencies.
> - Unaliased nested module references (e.g., Ltix.Foo.Bar.baz() instead of aliasing Bar).
> - Aliases that are imported but unused, or aliases not in alphabetical order.
> - Duplicated logic across modules that should be extracted.
>
> 6. Security & Correctness
> - Timing-sensitive comparisons on secrets (should use constant-time comparison).
> - Hardcoded secrets, keys, or credentials anywhere.
> - URLs constructed via string interpolation without validation/escaping.
> - Missing input validation at system boundaries.
>
> For each finding, report:
> - File path and line number(s)
> - Category (from above)
> - What the issue is
> - Why it matters
> - Suggested fix (one sentence)
>
> Sort findings by severity (most impactful first). Group by file. If no issues are found, simply report that the code looks clean.

## Output Format

After all checks complete, present a summary:

```
## QC Results

**Formatting**: PASS / FAIL (details if fail)
**Credo**: PASS / N issues found (list them)
**Test Review**: PASS / N issues found (list them)
```

If everything passes, just say: **QC: All checks pass.**
