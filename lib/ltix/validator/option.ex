defmodule Ltix.Validator.Option do
  @moduledoc false
  # The condition `Ltix.Validator.option/1` builds.

  @behaviour Ltix.Validator.Condition

  @impl Ltix.Validator.Condition
  def met?([key], _claims, opts), do: Keyword.get(opts, key, false) == true

  @impl Ltix.Validator.Condition
  def describe([key]), do: "the `#{inspect(key)}` option is set"
end
