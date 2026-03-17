defmodule Ltix.Errors.Invalid.RosterTooLarge do
  @moduledoc "Roster exceeds the max_members safety limit."
  use Ltix.Errors, fields: [:count, :max, :spec_ref], class: :invalid

  def message(%{count: count, max: max}) do
    "Roster exceeds max_members limit (#{count} > #{max}); use stream_members/2 for large rosters or set a higher limit"
  end
end
