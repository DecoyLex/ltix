defmodule Ltix.Errors.Unknown.TransportError do
  @moduledoc """
  HTTP or connection error from a platform endpoint.

  The following fields of this exception are public and can be accessed freely.

    * `:status` (`t:integer/0` or `nil`) - the HTTP status, or `nil` when no response arrived
    * `:body` (`t:term/0`) - the response body, or a description of the connection error
    * `:headers` (`t:map/0` or `nil`) - the response headers, such as `"retry-after"`
    * `:url` (`t:String.t/0` or `nil`) - the requested URL
  """
  use Ltix.Errors, fields: [:status, :body, :headers, :url], class: :unknown

  def message(%{status: status} = error) when not is_nil(status) do
    "HTTP #{status}#{location(error, "from")}"
  end

  def message(%{body: body} = error) do
    body = if is_binary(body), do: body, else: inspect(body)
    "Transport error#{location(error, "for")}: #{body}"
  end

  defp location(%{url: nil}, _preposition), do: ""
  defp location(%{url: url}, preposition), do: " #{preposition} #{url}"
end
