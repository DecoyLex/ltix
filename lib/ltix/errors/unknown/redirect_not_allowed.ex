defmodule Ltix.Errors.Unknown.RedirectNotAllowed do
  @moduledoc """
  A platform endpoint returned an unsafe or invalid redirect.
  """
  use Ltix.Errors, fields: [:status, :url, :location], class: :unknown

  def message(%{status: status, url: url, location: location}) do
    target =
      case location do
        nil -> "No valid redirect URL was provided."
        location -> "The redirect target is #{location}."
      end

    "HTTP #{status} redirect from #{url}. #{target} " <>
      "Platform redirects require a valid target on the same HTTPS origin"
  end
end
