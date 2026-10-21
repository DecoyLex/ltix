defmodule Ltix.Property do
  @moduledoc """
  One JSON property, such as a claim or a field of an object claim.

  Every property works the same way. Its options declare its JSON name and its
  Elixir name, `c:parse/2` reads its value from JSON, and `c:serialize/2`
  writes it back. A claim's options are `:claim` and `:name`, and
  `use Ltix.Claim` gives a claim module a `c:parse/2` that applies its
  `:schema` option.

  For a value it can't parse, `c:parse/2` returns `{:error, reason}`, with a
  message, an exception, or the errors of `Zoi.parse/2` as the reason.

      @impl Ltix.Property
      def parse(value, _opts), do: Zoi.parse(Zoi.list(Zoi.string()), value)
  """

  @doc """
  Parses the property's JSON value.

  Receives the property's options. The default returns the value unchanged.
  """
  @callback parse(json :: term(), opts :: term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Serializes a parsed value back to JSON.

  Receives the property's options. The default returns the value unchanged.
  """
  @callback serialize(value :: term(), opts :: term()) :: term()

  defmacro __using__(_opts) do
    quote do
      require Ltix.Behaviour

      Ltix.Behaviour.declare_once Ltix.Property do
        @doc false
        def parse(json, _opts), do: {:ok, json}

        @doc false
        def serialize(value, _opts), do: value

        defoverridable parse: 2, serialize: 2
      end
    end
  end
end
