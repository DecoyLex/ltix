defmodule Ltix.Errors.Invalid.InvalidClaim do
  @moduledoc "Claim present but wrong value or format."
  use Ltix.Errors, fields: [:claim, :value, :message, :spec_ref], class: :invalid

  def message(%{claim: claim, spec_ref: ref} = error) do
    "Invalid LTI claim #{claim}: #{description(error)}" <> if(ref, do: " [#{ref}]", else: "")
  end

  defp description(%{message: nil, value: value}), do: "got #{inspect(value)}"
  defp description(%{message: message, value: value}), do: "#{message} (got #{inspect(value)})"
end
