defmodule Ltix.PluginTest do
  use ExUnit.Case, async: true

  doctest Ltix.Ordered
  doctest Ltix.Plugin
  doctest Ltix.PluginSet
  doctest Ltix.PluginSet.Conflict
  doctest Ltix.Step
end
