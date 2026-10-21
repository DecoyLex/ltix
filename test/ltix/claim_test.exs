defmodule Ltix.ClaimTest do
  use ExUnit.Case, async: true

  doctest Ltix.Claim

  @object_claims [
    Ltix.Claims.ActualUser,
    Ltix.Claims.Context,
    Ltix.Claims.LaunchPresentation,
    Ltix.Claims.LIS,
    Ltix.Claims.Organization,
    Ltix.Claims.ResourceLink,
    Ltix.Claims.ToolPlatform,
    Ltix.DeepLinking.Settings,
    Ltix.GradeService.Endpoint,
    Ltix.MembershipsService.Endpoint
  ]

  describe "generated docs" do
    test "list an object claim's fields in order under one Fields heading" do
      for claim <- @object_claims do
        [_intro, listed] = String.split(moduledoc(claim), "## Fields")

        documented = Regex.scan(~r/^\* `:(\w+)`/m, listed, capture: :all_but_first)
        fields = Enum.map(Ltix.Type.fields(claim), fn {field, _schema} -> field end)

        assert Enum.map(documented, fn [field] -> String.to_existing_atom(field) end) == fields
      end
    end

    test "mark the required fields and include each field's description" do
      [_intro, listed] = String.split(moduledoc(Ltix.DeepLinking.Settings), "## Fields")

      assert listed =~
               "* `:deep_link_return_url` (`t:String.t/0`) - Required. Where your tool posts the response."

      assert listed =~
               "* `:accept_multiple` (`t:boolean/0`) - Whether the response can have several content items."
    end

    test "respect a moduledoc of false" do
      assert {:docs_v1, _, _, _, :hidden, _, _} = Code.fetch_docs(TestPlugins.UndocumentedSession)
    end
  end

  defp moduledoc(module) do
    {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(module)
    moduledoc
  end
end
