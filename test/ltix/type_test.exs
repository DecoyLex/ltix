defmodule Ltix.TypeTest do
  use ExUnit.Case, async: true

  alias Ltix.Claims.Context
  alias Ltix.MembershipsService.MembershipContainer

  doctest Ltix.Type
  doctest Ltix.Property

  defmodule Checked do
    use Ltix.Type,
      fields: [
        code:
          Zoi.string()
          |> Zoi.length(4)
          |> Zoi.optional(),
        due_on:
          Zoi.date()
          |> Zoi.min(~D[2026-01-01])
          |> Zoi.optional(),
        email: Zoi.email() |> Zoi.optional(),
        grades:
          Zoi.list(Zoi.integer())
          |> Zoi.max(2)
          |> Zoi.optional(),
        label:
          Zoi.string()
          |> Zoi.min(3)
          |> Zoi.optional(),
        level: Zoi.enum([:low, :high]) |> Zoi.optional(),
        pair: Zoi.tuple({Zoi.integer(), Zoi.integer()}) |> Zoi.optional(),
        count:
          Zoi.integer()
          |> Zoi.positive()
          |> Zoi.optional(),
        url:
          Zoi.string()
          |> Zoi.starts_with("https://")
          |> Zoi.optional(),
        version: Zoi.literal("1.3.0") |> Zoi.optional(),
        weight: Zoi.integer() |> Zoi.optional()
      ]
  end

  defmodule Endpoint do
    use Ltix.Type, fields: [events_url: Ltix.Type.url(description: "The events URL.")]
  end

  defmodule NamedEndpoint do
    use Ltix.Type, fields: [events_url: Ltix.Type.url(error: "must be the events URL")]
  end

  describe "new/3" do
    test "describes each failed check after the field's name" do
      for {field, value, message} <- [
            {:code, "abc", ~s(must have exactly 4 characters (got "abc"\))},
            {:due_on, ~D[2025-12-31], "must be at least 2026-01-01 (got ~D[2025-12-31])"},
            {:email, "ada", ~s(must be a valid email (got "ada"\))},
            {:grades, [1, 2, 3], "must have at most 2 items (got [1, 2, 3])"},
            {:label, "ab", ~s(must have at least 3 characters (got "ab"\))},
            {:level, :middle, "must be one of low, high (got :middle)"},
            {:pair, {1}, "must have 2 elements (got {1})"},
            {:count, 0, "must be greater than 0 (got 0)"},
            {:url, "http://a", ~s(must start with 'https://' (got "http://a"\))},
            {:version, "1.2", ~s(must be "1.3.0" (got "1.2"\))},
            {:weight, "heavy", ~s(must be an integer (got "heavy"\))}
          ] do
        assert {:error, error} = Ltix.Type.new(Checked, [{field, value}])

        assert Exception.message(error) ==
                 "Ltix.TypeTest.Checked field #{inspect(field)} #{message}"
      end
    end

    test "accepts a URL Ltix can send requests to in a URL field" do
      for url <- [
            "https://platform.example.com/events",
            "HTTPS://platform.example.com:8443/events",
            "http://localhost:4000/events",
            "http://10.0.0.5/events"
          ] do
        assert Ltix.Type.new(Endpoint, events_url: url) == {:ok, %Endpoint{events_url: url}}
      end
    end

    test "rejects a URL Ltix won't send requests to in a URL field" do
      for {url, message} <- [
            {"http://platform.example.com/events",
             ~s(must be an absolute HTTPS URL (got "http://platform.example.com/events"\))},
            {"https://user:secret@platform.example.com/events",
             ~s(must be an absolute HTTPS URL (got "https://user:secret@platform.example.com/events"\))},
            {"https://platform.example.com:0/events",
             ~s(must be an absolute HTTPS URL (got "https://platform.example.com:0/events"\))},
            {"/events", ~s(must be an absolute HTTPS URL (got "/events"\))},
            {:events, "must be an absolute HTTPS URL (got :events)"}
          ] do
        assert {:error, error} = Ltix.Type.new(Endpoint, events_url: url)
        assert Exception.message(error) == "Ltix.TypeTest.Endpoint field :events_url #{message}"
      end
    end

    test "reports a URL field's own error for every URL it rejects" do
      for {url, message} <- [
            {"http://platform.example.com/events",
             ~s(must be the events URL (got "http://platform.example.com/events"\))},
            {:events, "must be the events URL (got :events)"}
          ] do
        assert {:error, error} = Ltix.Type.new(NamedEndpoint, events_url: url)

        assert Exception.message(error) ==
                 "Ltix.TypeTest.NamedEndpoint field :events_url #{message}"
      end
    end

    test "takes an empty list for a list field" do
      assert {:ok, %Context{id: "c", type: []}} = Ltix.Type.new(Context, id: "c", type: [])
    end

    test "takes another type's struct for a field of that type" do
      context = %Context{id: "c", extensions: %{section: "A"}}

      assert {:ok, %MembershipContainer{context: ^context, members: []}} =
               Ltix.Type.new(MembershipContainer, context: context, members: [])
    end
  end
end
