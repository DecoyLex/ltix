defmodule Ltix.Credo.DoctestOutputTest do
  use Credo.Test.Case

  alias Ltix.Credo.DoctestOutput

  test "flags a doctest that compares and shows true or false" do
    ~S'''
    defmodule Example do
      @doc """
      Adds two numbers.

          iex> Example.add(1, 2) == 3
          true

          iex> match?({:ok, _}, Example.fetch(1))
          true

          iex> Example.add(1, 2)
          ...> |> Kernel.!=(4)
          true
      """
      def add(a, b), do: a + b
    end
    '''
    |> to_source_file()
    |> run_check(DoctestOutput)
    |> assert_issues_match([%{line_no: 5}, %{line_no: 8}, %{line_no: 11}])
  end

  test "accepts a predicate that shows true or false" do
    ~S'''
    defmodule Example do
      @doc """
      Returns whether the roles include an instructor.

          iex> Example.instructor?(["http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor"])
          true
      """
      def instructor?(roles), do: roles != []
    end
    '''
    |> to_source_file()
    |> run_check(DoctestOutput)
    |> refute_issues()
  end
end
