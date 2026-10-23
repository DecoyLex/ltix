defmodule Ltix.Errors.Security.AuthenticationFailed do
  @moduledoc "Platform returned an authentication error response."
  use Ltix.Errors, fields: [:error, :error_description, :error_uri], class: :security

  def message(%{error: error, error_description: description}) when description in [nil, ""],
    do: "Platform authentication failed: #{error}"

  def message(%{error: error, error_description: description}),
    do: "Platform authentication failed: #{error}. #{description}"
end
