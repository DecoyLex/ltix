defprotocol Ltix.DeepLinking.ContentItem do
  @moduledoc """
  Protocol for serializing content items in Deep Linking responses.

  Ltix implements this protocol for the five standard content item types
  and for plain maps (for one-off custom types).
  Implement this protocol on your own struct when you need a reusable
  custom content item type.

      defmodule MyApp.ProctoredExam do
        defstruct [:url, :title, :duration_minutes]

        defimpl Ltix.DeepLinking.ContentItem do
          def to_map(item) do
            %{
              "type" => "https://myapp.example.com/proctored_exam",
              "url" => item.url,
              "title" => item.title,
              "https://myapp.example.com/duration" => item.duration_minutes
            }
          end
        end
      end

  The platform's `accept_types` must include the `"type"` your `to_map/1`
  returns.
  """

  @doc """
  Serialize the content item to a JSON-compatible map.

  Plain maps with a `"type"` key serialize as they are.

  ## Examples

      iex> Ltix.DeepLinking.ContentItem.to_map(%{"type" => "https://vendor.example.com/poll", "question" => "Ready?"})
      %{"type" => "https://vendor.example.com/poll", "question" => "Ready?"}
  """
  @spec to_map(t) :: %{String.t() => any()}
  def to_map(content_item)
end

defimpl Ltix.DeepLinking.ContentItem, for: Map do
  def to_map(map), do: map
end
