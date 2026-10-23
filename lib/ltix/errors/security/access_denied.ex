defmodule Ltix.Errors.Security.AccessDenied do
  @moduledoc "Platform denied access to a service request or key set fetch."
  use Ltix.Errors, fields: [:status, :body, :url], class: :security

  def message(%{status: status, url: url}) do
    "Access denied for #{url} (HTTP #{status})"
  end
end
