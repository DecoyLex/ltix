defmodule Ltix.Errors.Security.LocalNetworkAccessDenied do
  @moduledoc "A platform request connected to a local or loopback address that isn't allowed."
  use Ltix.Errors, fields: [:url, :address_space], class: :security

  def message(%{url: url, address_space: address_space}) do
    "Request to #{url} was refused because it connects to a #{address_space} address. " <>
      "Set :local_network_access to allow it"
  end
end
