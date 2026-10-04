defmodule Ltix.DeepLinkingTest do
  use ExUnit.Case, async: true

  alias Ltix.DeepLinking
  alias Ltix.DeepLinking.ContentItem.File
  alias Ltix.DeepLinking.ContentItem.HTMLFragment
  alias Ltix.DeepLinking.ContentItem.Image
  alias Ltix.DeepLinking.ContentItem.Link
  alias Ltix.DeepLinking.ContentItem.LTIResourceLink
  alias Ltix.DeepLinking.Response
  alias Ltix.Errors.Invalid.ContentItemsExceedLimit
  alias Ltix.Errors.Invalid.ContentItemTypeNotAccepted
  alias Ltix.Errors.Invalid.InvalidContentItem
  alias Ltix.Errors.Invalid.InvalidMessageType
  alias Ltix.Errors.Invalid.LineItemNotAccepted

  @lti "https://purl.imsglobal.org/spec/lti/claim/"
  @dl "https://purl.imsglobal.org/spec/lti-dl/claim/"

  # Forwards events emitted by the test process, ignoring concurrent tests.
  def forward_own_event(event, _measurements, metadata, {test_pid, ref}) do
    if self() == test_pid, do: send(test_pid, {ref, List.last(event), metadata})
  end

  setup do
    %{platform: Ltix.Test.setup_platform!()}
  end

  describe "build_response/3 message type validation" do
    test "returns InvalidMessageType for resource link context", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, roles: [:instructor])

      assert {:error, %InvalidMessageType{message_type: "LtiResourceLinkRequest"}} =
               DeepLinking.build_response(context)
    end
  end

  describe "build_response/3 happy path" do
    test "empty items returns ok with signed JWT", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)

      assert {:ok, %Response{jwt: jwt, return_url: url}} =
               DeepLinking.build_response(context)

      assert [_, _, _] = String.split(jwt, ".")
      assert url == "https://platform.example.com/deep_links"
    end

    test "JWT is verifiable with tool's public key", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(context)

      assert {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)
      assert claims["iss"] == p.registration.client_id
      assert claims["aud"] == p.registration.issuer
      assert claims["azp"] == p.registration.issuer
    end

    test "JWT contains required LTI claims", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(context)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      assert claims[@lti <> "message_type"] == "LtiDeepLinkingResponse"
      assert claims[@lti <> "version"] == "1.3.0"
      assert claims[@lti <> "deployment_id"] == p.deployment.deployment_id
    end

    test "JWT has correct exp/iat/nonce", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(context)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      now = System.system_time(:second)
      assert claims["iat"] >= now - 1
      assert claims["exp"] - claims["iat"] == 300
      assert byte_size(claims["nonce"]) > 0
    end

    test "JWT header has kid and RS256 alg", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(context)

      %JOSE.JWS{alg: {_mod, alg}, fields: header} = JOSE.JWT.peek_protected(jwt)
      assert header["kid"] == p.registration.tool_jwk.kid
      assert alg == :RS256
    end

    test "empty items produces empty content_items array", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(context)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      assert claims[@dl <> "content_items"] == []
    end
  end

  describe "build_response/3 content item serialization" do
    test "serializes a Link item", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, link} = Link.new(url: "https://example.com")

      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(context, [link])
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      assert [%{"type" => "link", "url" => "https://example.com"}] =
               claims[@dl <> "content_items"]
    end

    test "serializes an LTIResourceLink item", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)

      {:ok, item} =
        LTIResourceLink.new(
          url: "https://tool.example.com",
          title: "Quiz",
          line_item: %{score_maximum: 100}
        )

      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(context, [item])
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      [ci] = claims[@dl <> "content_items"]
      assert ci["type"] == "ltiResourceLink"
      assert ci["lineItem"]["scoreMaximum"] == 100
    end

    test "passes through raw map items", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      raw = %{"type" => "link", "url" => "https://raw.example.com"}

      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(context, [raw])
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      assert [%{"type" => "link", "url" => "https://raw.example.com"}] =
               claims[@dl <> "content_items"]
    end
  end

  describe "build_response/3 data echoing" do
    test "echoes data from deep_linking_settings", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{data: "csrf:abc123"}
        )

      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(context)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      assert claims[@dl <> "data"] == "csrf:abc123"
    end

    test "omits data when not present in settings", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(context)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      refute Map.has_key?(claims, @dl <> "data")
    end
  end

  describe "build_response/3 message options" do
    test "includes message and log in JWT", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)

      {:ok, %Response{jwt: jwt}} =
        DeepLinking.build_response(context, [], message: "Done", log: "debug info")

      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      assert claims[@dl <> "msg"] == "Done"
      assert claims[@dl <> "log"] == "debug info"
    end

    test "includes errormsg and errorlog in JWT", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)

      {:ok, %Response{jwt: jwt}} =
        DeepLinking.build_response(context, [],
          error_message: "Oops",
          error_log: "stack trace"
        )

      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      assert claims[@dl <> "errormsg"] == "Oops"
      assert claims[@dl <> "errorlog"] == "stack trace"
    end

    test "raises on unknown and invalid options", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      resource_link_context = Ltix.Test.build_launch_context(p)

      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :msg is unknown", fn ->
        DeepLinking.build_response(context, [], msg: "Done")
      end

      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :msg is unknown", fn ->
        DeepLinking.build_response(resource_link_context, [], msg: "Done")
      end

      error =
        assert_raise Ltix.Errors.Invalid.InvalidOption, fn ->
          DeepLinking.build_response(context, [], log: 123)
        end

      assert %{key: :log, value: 123} = error
    end

    test "omits absent message options from JWT", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(context)
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      refute Map.has_key?(claims, @dl <> "msg")
      refute Map.has_key?(claims, @dl <> "log")
      refute Map.has_key?(claims, @dl <> "errormsg")
      refute Map.has_key?(claims, @dl <> "errorlog")
    end
  end

  describe "build_response/3 type validation" do
    test "rejects item type not in accept_types", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["ltiResourceLink"]}
        )

      {:ok, link} = Link.new(url: "https://example.com")

      assert {:error, %ContentItemTypeNotAccepted{index: 0, type: "link"}} =
               DeepLinking.build_response(context, [link])
    end

    test "rejects raw map with type not in accept_types", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["link"]}
        )

      raw = %{"type" => "https://example.com/custom", "data" => "x"}

      assert {:error, %ContentItemTypeNotAccepted{type: "https://example.com/custom"}} =
               DeepLinking.build_response(context, [raw])
    end

    test "checks a custom item by the type it serializes", %{platform: p} do
      poll = %CustomContentItem{question: "Ready?"}

      accepting =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["https://vendor.example.com/poll"]}
        )

      rejecting =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["link"]}
        )

      assert {:ok, %Response{jwt: jwt}} = DeepLinking.build_response(accepting, [poll])
      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, jwt)

      assert [%{"type" => "https://vendor.example.com/poll", "question" => "Ready?"}] =
               claims[@dl <> "content_items"]

      assert {:error, %ContentItemTypeNotAccepted{type: "https://vendor.example.com/poll"}} =
               DeepLinking.build_response(rejecting, [poll])
    end

    test "accepts item type in accept_types", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["link"]}
        )

      {:ok, link} = Link.new(url: "https://example.com")

      assert {:ok, %Response{}} = DeepLinking.build_response(context, [link])
    end
  end

  describe "build_response/3 multiplicity validation" do
    test "rejects multiple items when accept_multiple is false", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["link"], accept_multiple: false}
        )

      {:ok, l1} = Link.new(url: "https://a.com")
      {:ok, l2} = Link.new(url: "https://b.com")

      assert {:error, %ContentItemsExceedLimit{count: 2}} =
               DeepLinking.build_response(context, [l1, l2])
    end

    test "allows single item when accept_multiple is false", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["link"], accept_multiple: false}
        )

      {:ok, link} = Link.new(url: "https://a.com")

      assert {:ok, %Response{}} = DeepLinking.build_response(context, [link])
    end

    test "allows multiple items when accept_multiple is nil", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["link"], accept_multiple: nil}
        )

      {:ok, l1} = Link.new(url: "https://a.com")
      {:ok, l2} = Link.new(url: "https://b.com")

      assert {:ok, %Response{}} = DeepLinking.build_response(context, [l1, l2])
    end

    test "allows multiple items when accept_multiple is true", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["link"], accept_multiple: true}
        )

      {:ok, l1} = Link.new(url: "https://a.com")
      {:ok, l2} = Link.new(url: "https://b.com")

      assert {:ok, %Response{}} = DeepLinking.build_response(context, [l1, l2])
    end

    test "empty items with accept_multiple false succeeds", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_multiple: false}
        )

      assert {:ok, %Response{}} = DeepLinking.build_response(context, [])
    end
  end

  describe "build_response/3 line item validation" do
    test "rejects line_item when accept_line_item is false", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["ltiResourceLink"], accept_line_item: false}
        )

      {:ok, item} = LTIResourceLink.new(line_item: %{score_maximum: 100})

      assert {:error, %LineItemNotAccepted{index: 0}} =
               DeepLinking.build_response(context, [item])
    end

    test "allows line_item when accept_line_item is true", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["ltiResourceLink"], accept_line_item: true}
        )

      {:ok, item} = LTIResourceLink.new(line_item: %{score_maximum: 100})

      assert {:ok, %Response{}} = DeepLinking.build_response(context, [item])
    end

    test "allows LTIResourceLink without line_item when accept_line_item is false", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{accept_types: ["ltiResourceLink"], accept_line_item: false}
        )

      {:ok, item} = LTIResourceLink.new(url: "https://tool.example.com")

      assert {:ok, %Response{}} = DeepLinking.build_response(context, [item])
    end
  end

  describe "build_response/3 with several violations" do
    test "returns every violation, naming each item", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{
            accept_types: ["ltiResourceLink"],
            accept_multiple: false,
            accept_line_item: false
          }
        )

      {:ok, link} = Link.new(url: "https://example.com")
      {:ok, resource} = LTIResourceLink.new(line_item: [score_maximum: 10])
      {:ok, file} = File.new(url: "https://example.com/f.pdf")

      assert {:error, %Ltix.Errors.Invalid{errors: errors} = error} =
               DeepLinking.build_response(context, [link, resource, file])

      assert [
               %ContentItemTypeNotAccepted{
                 index: 0,
                 type: "link",
                 accept_types: ["ltiResourceLink"]
               },
               %LineItemNotAccepted{index: 1},
               %ContentItemTypeNotAccepted{index: 2, type: "file"},
               %ContentItemsExceedLimit{count: 3}
             ] = errors

      assert Exception.message(error) =~ "Content item at index 1 includes a line_item"
    end
  end

  describe "build_response/3 malformed items" do
    test "returns an error for a map without a \"type\" key", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      item = %{url: "https://example.com", type: "link"}

      assert {:error, %InvalidContentItem{index: 0, value: ^item} = error} =
               DeepLinking.build_response(context, [item])

      assert Exception.message(error) =~ "Content item at index 0 has no \"type\""
    end

    test "returns an error for a type that is not a string", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)

      assert {:error, %InvalidContentItem{index: 0, value: :link} = error} =
               DeepLinking.build_response(context, [%{"type" => :link}])

      assert Exception.message(error) =~
               "Content item at index 0 has a \"type\" that is not a string"
    end

    test "returns an error for a value that is not a content item", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, link} = Link.new(url: "https://example.com")

      assert {:error, %InvalidContentItem{index: 1, value: "https://example.com"} = error} =
               DeepLinking.build_response(context, [link, "https://example.com"])

      assert Exception.message(error) =~ "Content item at index 1 is not a content item"
    end

    test "returns an error for items that are not a list", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, link} = Link.new(url: "https://example.com")

      assert {:error, %InvalidContentItem{index: nil, value: ^link} = error} =
               DeepLinking.build_response(context, link)

      assert Exception.message(error) =~ "Content items must be a list"
    end

    test "groups every malformed item", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)

      assert {:error,
              %Ltix.Errors.Invalid{
                errors: [
                  %InvalidContentItem{index: 0},
                  %InvalidContentItem{index: 1}
                ]
              }} = DeepLinking.build_response(context, [%{}, nil])
    end
  end

  describe "build_response/3 telemetry" do
    setup do
      ref = make_ref()

      :telemetry.attach_many(
        ref,
        [
          [:ltix, :deep_linking, :build_response, :start],
          [:ltix, :deep_linking, :build_response, :stop]
        ],
        &__MODULE__.forward_own_event/4,
        {self(), ref}
      )

      on_exit(fn -> :telemetry.detach(ref) end)
      %{ref: ref}
    end

    test "reports the item count and types", %{platform: p, ref: ref} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, link} = Link.new(url: "https://example.com")
      {:ok, image} = Image.new(url: "https://example.com/i.png")

      {:ok, _} = DeepLinking.build_response(context, [link, image, link])

      assert_received {^ref, :start, %{item_count: 3, item_types: ["link", "image"]}}
      assert_received {^ref, :stop, %{item_count: 3, item_types: ["link", "image"]}}
    end

    test "brackets calls that return an error", %{platform: p, ref: ref} do
      deep_linking = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      resource_link = Ltix.Test.build_launch_context(p)

      {:error, _} = DeepLinking.build_response(deep_linking, :not_a_list)
      assert_received {^ref, :start, %{item_count: 0, item_types: []}}
      assert_received {^ref, :stop, _}

      {:error, _} = DeepLinking.build_response(resource_link, [])
      assert_received {^ref, :start, %{item_count: 0, item_types: []}}
      assert_received {^ref, :stop, %{item_count: 0, item_types: []}}
    end
  end

  describe "build_response/3 round-trip" do
    test "round-trips all content item types plus raw map", %{platform: p} do
      context =
        Ltix.Test.build_launch_context(p,
          message_type: :deep_linking,
          deep_linking_settings: %{data: "echo-me"}
        )

      {:ok, link} = Link.new(url: "https://example.com")

      {:ok, resource} =
        LTIResourceLink.new(
          url: "https://tool.example.com",
          line_item: %{score_maximum: 100, label: "Quiz"}
        )

      {:ok, file} = File.new(url: "https://example.com/f.pdf")
      {:ok, html} = HTMLFragment.new(html: "<p>Hi</p>")
      {:ok, image} = Image.new(url: "https://example.com/i.png")
      raw = %{"type" => "link", "url" => "https://raw.example.com"}

      {:ok, response} =
        DeepLinking.build_response(
          context,
          [link, resource, file, html, image, raw],
          message: "Selected 6 items"
        )

      {:ok, claims} = Ltix.Test.verify_deep_linking_response(p, response.jwt)

      items = claims[@dl <> "content_items"]
      assert length(items) == 6

      types = Enum.map(items, & &1["type"])
      assert types == ["link", "ltiResourceLink", "file", "html", "image", "link"]

      assert claims[@dl <> "data"] == "echo-me"
      assert claims[@dl <> "msg"] == "Selected 6 items"
      assert response.return_url == "https://platform.example.com/deep_links"
    end
  end

  describe "verify_deep_linking_response/2" do
    test "returns error for tampered JWT", %{platform: p} do
      context = Ltix.Test.build_launch_context(p, message_type: :deep_linking)
      {:ok, response} = DeepLinking.build_response(context)

      assert {:error, :signature_invalid} =
               Ltix.Test.verify_deep_linking_response(p, response.jwt <> "tampered")
    end
  end
end
