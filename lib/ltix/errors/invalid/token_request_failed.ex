defmodule Ltix.Errors.Invalid.TokenRequestFailed do
  @moduledoc "OAuth token request failed."
  use Ltix.Errors, fields: [:error, :error_description, :status, :body], class: :invalid

  def message(%{error: nil, status: status}),
    do: "OAuth token request failed (HTTP #{status})"

  def message(%{error: error, error_description: description}) when description in [nil, ""],
    do: "OAuth token request failed: #{error}"

  def message(%{error: error, error_description: description}),
    do: "OAuth token request failed: #{error}. #{description}"
end
