defmodule Ltix.Errors.Security.AccessDenied do
  @moduledoc "Platform denied access to a service request or key set fetch."
  use Ltix.Errors, fields: [:status, :body, :url, :spec_ref], class: :security

  def message(%{status: status, url: url, spec_ref: ref}) do
    "Access denied for #{url} (HTTP #{status}) [#{ref}]"
  end
end
