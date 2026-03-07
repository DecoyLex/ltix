---
name: qc
description: This skill should be used when the user says "/qc", "quality check", "check code quality", "run quality checks", or "check formatting and tests". It runs formatting, linting, and test review checks on the current codebase.
version: 0.1.0
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

Launch a Task subagent (`subagent_type: "Explore"`) with the following prompt:

> Review all test files in the `test/` directory for common test hygiene issues. Read every test file and check for these problems:
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

## Output Format

After all checks complete, present a summary:

```
## QC Results

**Formatting**: PASS / FAIL (details if fail)
**Credo**: PASS / N issues found (list them)
**Test Review**: PASS / N issues found (list them)
```

If everything passes, just say: **QC: All checks pass.**
