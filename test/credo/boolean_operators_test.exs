defmodule Ltix.Credo.BooleanOperatorsTest do
  use Credo.Test.Case

  alias Ltix.Credo.BooleanOperators

  test "flags and, or, and not outside guards" do
    """
    defmodule Example do
      def run(a, b, c) do
        x = a and b
        y = a or c
        not y
      end
    end
    """
    |> to_source_file()
    |> run_check(BooleanOperators)
    |> assert_issues_match([
      %{line_no: 3, trigger: "and"},
      %{line_no: 4, trigger: "or"},
      %{line_no: 5, trigger: "not"}
    ])
  end

  test "accepts and, or, and not in guards" do
    """
    defmodule Example do
      defguard present?(value) when not is_nil(value) and value != ""

      def run(a, b) when is_atom(a) or is_binary(b), do: a

      def classify(value) do
        case value do
          v when is_integer(v) and v > 0 -> :positive
          v when not is_integer(v) -> :other
        end
      end

      def pick(values), do: Enum.filter(values, fn v when v > 0 and v < 10 -> true end)
    end
    """
    |> to_source_file()
    |> run_check(BooleanOperators)
    |> refute_issues()
  end

  test "accepts not in" do
    """
    defmodule Example do
      def run(key, keys), do: key not in keys
    end
    """
    |> to_source_file()
    |> run_check(BooleanOperators)
    |> refute_issues()
  end
end
