# The key set cache is linked to the test runner process, so it runs for the
# entire test suite.
{:ok, _key_set} = Ltix.JWT.KeySet.start_link()

# Credo loads the project's checks from source, so the check tests do too.
# `mix precommit` runs `mix credo` first, which starts Credo's services itself.
if Process.whereis(Credo.Supervisor) == nil,
  do: {:ok, _apps} = Application.ensure_all_started(:credo)

for check <- Path.wildcard("credo/*.ex"), do: Code.require_file(check)

# A message a test waits for can arrive after ExUnit's default 100ms when
# other test suites run on the machine at the same time.
ExUnit.start(assert_receive_timeout: 1_000)
