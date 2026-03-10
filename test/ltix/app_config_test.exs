defmodule Ltix.AppConfigTest do
  use ExUnit.Case, async: true

  alias Ltix.AppConfig

  describe "pop_required!/2" do
    test "returns value from opts" do
      assert {MyModule, []} = AppConfig.pop_required!([foo: MyModule], :foo)
    end

    test "raises ArgumentError when key is missing" do
      assert_raise ArgumentError, ~r/bar/, fn ->
        AppConfig.pop_required!([], :bar)
      end
    end
  end
end
