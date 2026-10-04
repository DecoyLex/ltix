defmodule Ltix.Errors.Unknown.TransportError do
  @moduledoc "HTTP or connection error from a platform endpoint."
  use Ltix.Errors, fields: [:status, :body, :url, :spec_ref], class: :unknown

  def message(%{status: status} = error) when not is_nil(status) do
    "HTTP #{status}#{location(error, "from")}#{spec_ref(error)}"
  end

  def message(%{body: body} = error) do
    body = if is_binary(body), do: body, else: inspect(body)
    "Transport error#{location(error, "for")}: #{body}#{spec_ref(error)}"
  end

  defp location(%{url: nil}, _preposition), do: ""
  defp location(%{url: url}, preposition), do: " #{preposition} #{url}"

  defp spec_ref(%{spec_ref: nil}), do: ""
  defp spec_ref(%{spec_ref: ref}), do: " [#{ref}]"
end
