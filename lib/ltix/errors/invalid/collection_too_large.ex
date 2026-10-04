defmodule Ltix.Errors.Invalid.CollectionTooLarge do
  @moduledoc """
  An eager collection fetch exceeded its safety limit.

  The following fields of this exception are public and can be accessed freely.

    * `:option` (`t:atom/0`) - the limit option, such as `:max_members` or `:max_results`
    * `:count` (`t:non_neg_integer/0`) - the number of entries fetched when the limit was exceeded
  """
  use Ltix.Errors, fields: [:service, :option, :count, :max, :spec_ref], class: :invalid

  def message(%{service: service, option: option, count: count, max: max, spec_ref: ref}) do
    "#{inspect(service)} collection exceeds the #{option} limit (#{count} > #{max}). " <>
      "Stream large collections or set a higher limit [#{ref}]"
  end
end
