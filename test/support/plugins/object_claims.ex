defmodule TestPlugins.UndocumentedSession do
  @moduledoc false
  # An object claim whose moduledoc is `false`.
  use Ltix.Claim,
    claim: "https://tool.example.com/claim/undocumented_session",
    name: :undocumented_session,
    fields: [id: Zoi.string(description: "The session's ID.")]
end
