defmodule Ltix.Credo.OptionsDocsTest do
  use Credo.Test.Case

  alias Ltix.Credo.OptionsDocs

  test "flags a public function whose options its docs don't list" do
    ~S'''
    defmodule Example do
      @moduledoc "An example."

      @doc """
      Fetches the members. See the moduledoc for the options.
      """
      def list_members(client, opts \\ []), do: {client, opts}
    end
    '''
    |> to_source_file()
    |> run_check(OptionsDocs)
    |> assert_issue(%{line_no: 7, trigger: "list_members"})
  end

  test "flags options listed by hand" do
    ~S'''
    defmodule Example do
      @moduledoc "An example."

      @doc """
      Fetches the members.

      ## Options

        * `:per_page` - page size hint.
      """
      def list_members(client, opts \\ []), do: {client, opts}
    end
    '''
    |> to_source_file()
    |> run_check(OptionsDocs)
    |> assert_issue(%{line_no: 11})
  end

  test "accepts options listed with Zoi.describe" do
    ~S'''
    defmodule Example do
      @moduledoc "An example."

      @doc """
      Fetches the members.

      ## Options

      #{Zoi.describe(@list_members_schema)}
      """
      def list_members(client, opts \\ [])
      def list_members(client, opts) when is_list(opts), do: {client, opts}
    end
    '''
    |> to_source_file()
    |> run_check(OptionsDocs)
    |> refute_issues()
  end

  test "flags a bang function with no plain version to list its options" do
    ~S'''
    defmodule Example do
      @moduledoc "An example."

      @doc "Checks the adapter, and raises when it breaks the contract."
      def assert_adapter!(adapter, opts), do: {adapter, opts}
    end
    '''
    |> to_source_file()
    |> run_check(OptionsDocs)
    |> assert_issue(%{line_no: 5, trigger: "assert_adapter!"})
  end

  test "accepts functions whose options another page documents" do
    ~S'''
    defmodule Example do
      @moduledoc "An example."

      @impl Ltix.Plugin
      def plugin(opts), do: opts

      @doc false
      def internal(opts), do: opts

      @doc """
      Fetches the example.

      ## Options

      #{Zoi.describe(@fetch_schema)}
      """
      def fetch(opts), do: {:ok, opts}

      @doc "Same as `fetch/1` but raises on error."
      def fetch!(opts), do: opts
    end

    defmodule Example.Hidden do
      @moduledoc false

      @doc "Runs the example."
      def run(opts), do: opts
    end
    '''
    |> to_source_file()
    |> run_check(OptionsDocs)
    |> refute_issues()
  end
end
