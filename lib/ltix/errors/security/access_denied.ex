defmodule Ltix.Errors.Security.AccessDenied do
  @moduledoc "Platform denied access to a service request."
  use Splode.Error, fields: [:service, :status, :body, :spec_ref], class: :security

  def message(%{service: service, status: status, spec_ref: ref}) do
    "Access denied for #{inspect(service)} (HTTP #{status}) [#{ref}]"
  end
end
