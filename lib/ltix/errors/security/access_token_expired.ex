defmodule Ltix.Errors.Security.AccessTokenExpired do
  @moduledoc "OAuth access token has expired."
  use Ltix.Errors, fields: [:expires_at], class: :security

  def message(%{expires_at: expires_at}) do
    "OAuth access token expired at #{expires_at}; call Client.refresh/1 to re-acquire"
  end
end
