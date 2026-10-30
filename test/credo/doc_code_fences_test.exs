defmodule Ltix.Credo.DocCodeFencesTest do
  use Credo.Test.Case

  alias Ltix.Credo.DocCodeFences

  test "flags indented code in a doc" do
    ~S'''
    defmodule Example do
      @moduledoc """
      An example.

          Example.run()
      """

      @doc """
      Runs the example.

          iex> Example.run()
          :ok
      """
      def run, do: :ok
    end
    '''
    |> to_source_file()
    |> run_check(DocCodeFences)
    |> assert_issues_match([%{line_no: 5}, %{line_no: 11}])
  end

  test "flags a fence that doesn't name its language" do
    ~S'''
    defmodule Example do
      @moduledoc """
      An example.

      ```
      Example.run()
      ```
      """
    end
    '''
    |> to_source_file()
    |> run_check(DocCodeFences)
    |> assert_issue(%{line_no: 5})
  end

  test "flags indented code inside a list item" do
    ~S'''
    defmodule Example do
      @moduledoc """
      An example.

        * `:req_options` - options for Req.

              config :ltix, req_options: [receive_timeout: 10_000]
      """
    end
    '''
    |> to_source_file()
    |> run_check(DocCodeFences)
    |> assert_issue(%{line_no: 7})
  end

  test "accepts a doc inside a string" do
    ~S'''
    defmodule ExampleTest do
      @source ~S[
      defmodule Example do
        @moduledoc """
        An example.

            Example.run()
        """
      end
      ]
    end
    '''
    |> to_source_file()
    |> run_check(DocCodeFences)
    |> refute_issues()
  end

  test "accepts fenced code and nested list items" do
    ~S'''
    defmodule Example do
      @moduledoc """
      An example.

      ```elixir
      iex> Example.run()
      :ok
      ```

        * `:auth` - sets request authentication.
          - `{:basic, userinfo}` - Basic HTTP authentication
      """
    end
    '''
    |> to_source_file()
    |> run_check(DocCodeFences)
    |> refute_issues()
  end
end
