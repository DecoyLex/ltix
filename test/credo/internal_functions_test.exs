defmodule Ltix.Credo.InternalFunctionsTest do
  use Credo.Test.Case

  alias Ltix.Credo.InternalFunctions

  test "flags a call outside quote to a double-underscore function defined outside quote" do
    plugin = """
    defmodule Example.Plugin do
      @doc false
      def __add_entry__(plugin, entry), do: %{plugin | entries: [entry | plugin.entries]}
    end
    """

    claim = """
    defmodule Example.Claim do
      def add(plugin, opts), do: Example.Plugin.__add_entry__(plugin, {__MODULE__, opts})
    end
    """

    [to_source_file(plugin, "plugin.ex"), to_source_file(claim, "claim.ex")]
    |> run_check(InternalFunctions)
    |> assert_issue(%{filename: "claim.ex", line_no: 2, trigger: "__add_entry__"})
  end

  test "accepts double-underscore functions that use defines or calls" do
    provider = """
    defmodule Example.Provider do
      defmacro __using__(opts) do
        quote do
          def __ltix_hook__, do: unquote(opts[:hook])
          def resolve(plugins), do: Example.Provider.__resolve__(plugins, __MODULE__)
        end
      end

      @doc false
      @spec __resolve__(term(), module()) :: {term(), [module()]}
      def __resolve__(plugins, provider), do: {plugins, provider.__ltix_hook__()}
    end
    """

    provider
    |> to_source_file()
    |> run_check(InternalFunctions)
    |> refute_issues()
  end
end
