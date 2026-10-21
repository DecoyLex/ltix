defmodule Ltix.Errors.Unknown.KeySetNotStarted do
  @moduledoc """
  The key set cache a launch needs is not running.

  The following fields of this exception are public and can be accessed freely.

    * `:key_set` (`t:atom/0`) - the name of the key set cache
  """
  use Ltix.Errors, fields: [:key_set], class: :unknown

  def message(%{key_set: key_set}) do
    child =
      if key_set == Ltix.JWT.KeySet,
        do: "Ltix.JWT.KeySet",
        else: "{Ltix.JWT.KeySet, name: #{inspect(key_set)}}"

    "Key set cache #{inspect(key_set)} is not started. " <>
      "Add #{child} to your application's supervision tree."
  end
end
