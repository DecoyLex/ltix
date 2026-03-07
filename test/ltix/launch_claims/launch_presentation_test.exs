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

    # [Core §5.4.4] All fields optional
    test "parses empty map" do
      assert {:ok,
              %LaunchPresentation{
                document_target: nil,
                height: nil,
                width: nil,
                return_url: nil,
                locale: nil
              }} = LaunchPresentation.from_json(%{})
    end

    # [Core §5.4.4] document_target MUST be one of frame, iframe, window
    test "accepts frame as document_target" do
      assert {:ok, %LaunchPresentation{document_target: "frame"}} =
               LaunchPresentation.from_json(%{"document_target" => "frame"})
    end

    test "accepts iframe as document_target" do
      assert {:ok, %LaunchPresentation{document_target: "iframe"}} =
               LaunchPresentation.from_json(%{"document_target" => "iframe"})
    end

    test "accepts window as document_target" do
      assert {:ok, %LaunchPresentation{document_target: "window"}} =
               LaunchPresentation.from_json(%{"document_target" => "window"})
    end

    # [Core §5.4.4] invalid document_target returns error
    test "rejects invalid document_target" do
      assert {:error, error} =
               LaunchPresentation.from_json(%{"document_target" => "popup"})

      assert Exception.message(error) =~ "document_target"
    end
  end
end
