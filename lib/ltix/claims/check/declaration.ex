defmodule Ltix.Claims.Check.Declaration do
  @moduledoc false
  # The part of `Ltix.Claims.Check`'s hook that checks the `use` options.

  @options [:claim, :message_types]

  defmacro __using__(opts) do
    Keyword.validate!(opts, @options)

    unless is_binary(opts[:claim]) do
      raise ArgumentError, "Ltix.Claims.Check requires the :claim option, the claim's URI"
    end

    message_types = Keyword.get(opts, :message_types, :all)

    unless message_types == :all ||
             (is_list(message_types) && Enum.all?(message_types, &is_binary/1)) do
      raise ArgumentError,
            "Ltix.Claims.Check's :message_types option must be a list of message type strings or :all, got #{Macro.to_string(message_types)}"
    end

    nil
  end
end
