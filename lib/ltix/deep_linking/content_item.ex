defprotocol Ltix.DeepLinking.ContentItem do
  @moduledoc """
  Protocol for serializing content items in Deep Linking responses.

  Ltix implements this protocol for the five standard content item types
  and for plain maps (as an escape hatch for one-off custom types).
  Implement this protocol on your own struct when you need a reusable
  custom content item type:

      defmodule MyApp.ProctoredExam do
        defstruct [:url, :title, :duration_minutes]

        defimpl Ltix.DeepLinking.ContentItem do
          def item_type(_item), do: "https://myapp.example.com/proctored_exam"

          def to_json(item) do
            %{
              "type" => "https://myapp.example.com/proctored_exam",
              "url" => item.url,
              "title" => item.title,
              "https://myapp.example.com/duration" => item.duration_minutes
            }
          end
        end
      end

  The platform's `accept_types` must include your custom type string.
  """

  @doc "Return the content item type string (e.g., `\"ltiResourceLink\"`)."
  @spec item_type(t) :: String.t()
  def item_type(content_item)

  @doc "Serialize the content item to a JSON-compatible map."
  @spec to_json(t) :: %{String.t() => any()}
  def to_json(content_item)
end

defimpl Ltix.DeepLinking.ContentItem, for: Map do
  def item_type(%{"type" => type}), do: type
  def item_type(_), do: raise(ArgumentError, "Invalid content item map: missing 'type' field")

  def to_json(map) when is_map(map), do: map
  def to_json(_), do: raise(ArgumentError, "Invalid content item: expected a map")
end
