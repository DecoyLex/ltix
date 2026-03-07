# Create the JWKS cache ETS table owned by the test runner process
# so it persists for the entire test suite (async-safe).
:ets.new(:ltix_jwks_cache, [:set, :public, :named_table])

ExUnit.start()
