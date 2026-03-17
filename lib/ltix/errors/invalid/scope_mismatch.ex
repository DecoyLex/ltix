defmodule Ltix.Errors.Invalid.ScopeMismatch do
  @moduledoc "Client lacks the required OAuth scope."
  use Ltix.Errors, fields: [:scope, :granted_scopes, :spec_ref], class: :invalid

  def message(%{scope: scope, spec_ref: ref}) do
    "Client is not authorized for scope #{scope}; authenticate with the correct endpoint [#{ref}]"
  end
end
