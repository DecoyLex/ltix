defmodule Ltix.Errors.Security.AccessTokenExpired do
  @moduledoc "OAuth access token has expired."
  use Splode.Error, fields: [:expires_at, :spec_ref], class: :security

  def message(%{expires_at: expires_at, spec_ref: ref}) do
    "OAuth access token expired at #{expires_at}; call Client.refresh/1 to re-acquire [#{ref}]"
  end
end
