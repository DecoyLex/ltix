defmodule Ltix.Errors.Invalid.ScopeMismatch do
  @moduledoc """
  Client lacks the required OAuth scope.

  The following fields of this exception are public and can be accessed freely.

    * `:scopes` (list of `t:String.t/0`) - the scopes that would authorize the request, none of which the client was granted
  """
  use Ltix.Errors, fields: [:scopes, :granted_scopes], class: :invalid

  def message(%{scopes: scopes}) do
    "Client is not authorized for scope #{Enum.join(scopes, " or ")}; " <>
      "authenticate with the correct endpoint"
  end
end
