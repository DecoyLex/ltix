defmodule Ltix.Errors.Unknown.TransportError do
  @moduledoc "HTTP or connection error from a platform endpoint."
  use Ltix.Errors, fields: [:status, :body, :url, :spec_ref], class: :unknown

  def message(%{status: status, url: url, spec_ref: ref}) when not is_nil(status) do
    "HTTP #{status} from #{url} [#{ref}]"
  end

  def message(%{body: body, spec_ref: ref}) do
    body_str = if is_binary(body), do: body, else: inspect(body)
    "Transport error: #{body_str} [#{ref}]"
  end
end
