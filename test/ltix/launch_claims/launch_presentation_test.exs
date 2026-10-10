defmodule Ltix.LaunchClaims.LaunchPresentationTest do
  use ExUnit.Case, async: true

  alias Ltix.LaunchClaims.LaunchPresentation

  doctest Ltix.LaunchClaims.LaunchPresentation

  describe "from_json/1" do
    test "parses all fields" do
      json = %{
        "document_target" => "iframe",
        "height" => 600,
        "width" => 800,
        "return_url" => "https://platform.example.com/return",
        "locale" => "en-US"
      }

      assert {:ok, %LaunchPresentation{} = lp} = LaunchPresentation.from_json(json)
      assert lp.document_target == "iframe"
      assert lp.height == 600
      assert lp.width == 800
      assert lp.return_url == "https://platform.example.com/return"
      assert lp.locale == "en-US"
    end
  end
end
