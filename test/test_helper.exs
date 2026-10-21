# The key set cache is linked to the test runner process, so it runs for the
# entire test suite.
{:ok, _key_set} = Ltix.JWT.KeySet.start_link()

ExUnit.start()
