defmodule CustomContentItem do
  @moduledoc false

  # A tool-defined content item type, serialized only through `to_map/1`.

  defstruct [:question]

  defimpl Ltix.DeepLinking.ContentItem do
    def to_map(poll) do
      %{"type" => "https://vendor.example.com/poll", "question" => poll.question}
    end
  end
end
