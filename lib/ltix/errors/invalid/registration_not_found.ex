defmodule Ltix.Errors.Invalid.RegistrationNotFound do
  @moduledoc "Unknown issuer/client_id combination [Sec §5.1.1.1]."
  use Ltix.Errors, fields: [:issuer, :client_id], class: :invalid

  def message(%{issuer: issuer, client_id: client_id}) do
    "Registration not found for issuer #{issuer}, client_id #{inspect(client_id)}"
  end
end
