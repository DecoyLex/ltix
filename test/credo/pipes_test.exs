defmodule Ltix.Credo.PipesTest do
  use Credo.Test.Case

  alias Ltix.Credo.Pipes

  test "flags a pipeline with one call" do
    """
    defmodule Example do
      def run(list), do: list |> Enum.sort()
    end
    """
    |> to_source_file()
    |> run_check(Pipes)
    |> assert_issue()
  end

  test "flags a pipeline that starts with a function call" do
    """
    defmodule Example do
      def run(list) do
        Enum.sort(list)
        |> Enum.take(5)
        |> Enum.sum()
      end
    end
    """
    |> to_source_file()
    |> run_check(Pipes)
    |> assert_issue()
  end

  test "accepts a pipeline that starts with a raw value" do
    """
    defmodule Example do
      def run(list) do
        list
        |> Enum.sort()
        |> Enum.take(5)
      end
    end
    """
    |> to_source_file()
    |> run_check(Pipes)
    |> refute_issues()
  end

  test "accepts builder chains that start with a call" do
    """
    defmodule Example do
      @schema Zoi.string() |> Zoi.optional()

      def plugin(_opts) do
        Plugin.new(name: "Example")
        |> Plugin.add(Example.Step)
      end

      def full_plugin(_opts) do
        Ltix.Plugin.new(name: "Example")
        |> Ltix.Plugin.add(Example.Step)
      end

      def validator do
        new("LtiResourceLinkRequest")
        |> required(:resource_link)
      end

      def fetch(url), do: Req.get!(url) |> Map.fetch!(:body)
    end
    """
    |> to_source_file()
    |> run_check(Pipes)
    |> refute_issues()
  end

  test "flags an Ltix builder call wrapped around new" do
    """
    defmodule Example do
      def plugin(opts) do
        Ltix.Plugin.add(
          Ltix.Plugin.new(name: "Blocklist"),
          {Blocklist.Login, issuers: opts[:issuers]}
        )
      end

      def validator, do: required(new("LtiResourceLinkRequest"), :resource_link)
    end
    """
    |> to_source_file()
    |> run_check(Pipes)
    |> assert_issues_match([%{line_no: 3}, %{line_no: 9}])
  end

  test "accepts a pipeline of Zoi calls from any schema" do
    """
    defmodule Example do
      @schema Ltix.Type.object(@window, description: "When it's open.") |> Zoi.optional()
    end
    """
    |> to_source_file()
    |> run_check(Pipes)
    |> refute_issues()
  end

  test "accepts a struct's own new" do
    """
    defmodule Example do
      def new(fields), do: struct!(__MODULE__, fields)

      def new!(fields) do
        case new(fields) do
          {:ok, example} -> example
          {:error, error} -> raise error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(Pipes)
    |> refute_issues()
  end

  test "accepts new as the first expression of a block" do
    """
    defmodule Example do
      def plugin(_opts) do
        Ltix.Plugin.new(name: "Example")
        :ok
      end
    end
    """
    |> to_source_file()
    |> run_check(Pipes)
    |> refute_issues()
  end

  test "accepts a pipeline that starts with an operator" do
    """
    defmodule Example do
      def run(prefix, name) do
        prefix <> name
        |> String.trim()
        |> String.upcase()
      end
    end
    """
    |> to_source_file()
    |> run_check(Pipes)
    |> refute_issues()
  end
end
