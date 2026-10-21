defmodule Ltix.Claims.Override.Declaration do
  @moduledoc false
  # The part of `Ltix.Claims.Override`'s hook that checks the `use` options.

  @options [:check, :message_types]

  defmacro __using__(opts) do
    Keyword.validate!(opts, @options)

    unless is_atom(Macro.expand(opts[:check], __CALLER__)) && opts[:check] != nil do
      raise ArgumentError,
            "Ltix.Claims.Override requires the :check option, the module whose check it replaces"
    end

    message_types = opts[:message_types]

    unless is_list(message_types) && message_types != [] &&
             Enum.all?(message_types, &is_binary/1) do
      raise ArgumentError,
            "Ltix.Claims.Override requires the :message_types option, a non-empty list of message type strings, got #{Macro.to_string(message_types)}"
    end

    nil
  end
end
