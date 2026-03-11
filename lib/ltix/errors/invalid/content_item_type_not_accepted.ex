defmodule Ltix.Errors.Invalid.ContentItemTypeNotAccepted do
  @moduledoc "Content item type not in the platform's accept_types list."
  use Splode.Error, fields: [:type, :accept_types, :spec_ref], class: :invalid

  # [DL §4.4.1](https://www.imsglobal.org/spec/lti-dl/v2p0/#deep-linking-settings)
  def message(%{type: type, accept_types: accepted, spec_ref: ref}) do
    "Content item type #{inspect(type)} is not accepted; " <>
      "platform accepts: #{inspect(accepted)} [#{ref}]"
  end
end
