defmodule Ltix.Validator.Includes do
  @moduledoc false
  # The condition `Ltix.Validator.includes/3` builds.

  @behaviour Ltix.Validator.Condition

  @impl Ltix.Validator.Condition
  def met?([claim, field, value], claims, _opts) do
    case claims do
      %{^claim => %{} = object} -> value in List.wrap(Map.get(object, field))
      _absent -> false
    end
  end

  @impl Ltix.Validator.Condition
  def describe([claim, field, value]), do: "`#{claim}.#{field}` includes `#{inspect(value)}`"
end
