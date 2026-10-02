defmodule Ltix.LaunchClaimsConfigTest do
  use ExUnit.Case

  alias Ltix.LaunchClaims

  setup do
    previous = Application.fetch_env(:ltix, LaunchClaims)

    on_exit(fn ->
      case previous do
        {:ok, configuration} -> Application.put_env(:ltix, LaunchClaims, configuration)
        :error -> Application.delete_env(:ltix, LaunchClaims)
      end
    end)
  end

  test "per-call parsers override configured parsers and retain other configured parsers" do
    claim_key = "https://example.com/override-test"
    configured_key = "https://example.com/configured-test"
    call_key = "https://example.com/call-test"
    json = %{claim_key => "raw", configured_key => "retained", call_key => "added"}

    config_parser = fn value -> {:ok, {:from_config, value}} end
    call_parser = fn value -> {:ok, {:from_call, value}} end

    Application.put_env(:ltix, LaunchClaims,
      claim_parsers: %{
        claim_key => config_parser,
        configured_key => config_parser
      }
    )

    assert {:ok, %LaunchClaims{extensions: baseline}} = LaunchClaims.from_json(json)
    assert baseline[claim_key] == {:from_config, "raw"}
    assert baseline[configured_key] == {:from_config, "retained"}
    assert baseline[call_key] == "added"

    assert {:ok, %LaunchClaims{extensions: extensions}} =
             LaunchClaims.from_json(json,
               parsers: %{claim_key => call_parser, call_key => call_parser}
             )

    assert extensions[claim_key] == {:from_call, "raw"}
    assert extensions[configured_key] == {:from_config, "retained"}
    assert extensions[call_key] == {:from_call, "added"}
  end
end
