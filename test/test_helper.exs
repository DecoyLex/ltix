# The key set cache is linked to the test runner process, so it runs for the
# entire test suite.
{:ok, _key_set} = Ltix.JWT.KeySet.start_link()

# Credo loads the project's checks from source, so the check tests do too.
# `mix precommit` runs `mix credo` first, which starts Credo's services itself.
if Process.whereis(Credo.Supervisor) == nil,
  do: {:ok, _apps} = Application.ensure_all_started(:credo)

for check <- Path.wildcard("credo/*.ex"), do: Code.require_file(check)

ExUnit.start()
