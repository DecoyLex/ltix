defmodule Ltix.Claim.Declaration do
  @moduledoc false
  # The part of `Ltix.Claim`'s hook that checks the `use` options and defines a
  # claim module's default `parse/2`. Its struct is a declared claim in a
  # plugin set, which `Ltix.Claims` builds from an entry when it resolves the
  # set. It has the entry's module and options, the claim's URI, short name,
  # the name its errors give, service, `:strict` option, and value when a
  # message lacks it.

  defstruct [
    :claim,
    :opts,
    :uri,
    :name,
    :label,
    :service,
    :strict,
    :default
  ]

  @type t :: %__MODULE__{
          claim: module(),
          opts: keyword(),
          uri: String.t(),
          name: atom(),
          label: String.t(),
          service: module() | nil,
          strict: boolean(),
          default: term()
        }

  @options [:claim, :name, :schema, :fields, :strict, :default, :service]

  defmacro __using__(opts) do
    case Keyword.keys(opts) -- @options do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown Ltix.Claim options: #{inspect(unknown)}"
    end

    for key <- [:claim, :name], !Keyword.has_key?(opts, key) do
      raise ArgumentError, "Ltix.Claim requires the #{inspect(key)} option"
    end

    check_values!(opts, __CALLER__)

    case Keyword.fetch(opts, :fields) do
      {:ok, fields} ->
        # An object claim is a provider. Its extenders each declare one of its
        # properties.
        quote do
          use Ltix.Provider, hook: [Ltix.Property]
          use Ltix.Type, fields: unquote(fields)

          @before_compile Ltix.Type

          @impl Ltix.Property
          def parse(json, _opts) do
            Ltix.Type.from_json(__MODULE__, json, name: unquote(Atom.to_string(opts[:name])))
          end

          defoverridable parse: 2
        end

      :error ->
        quote do
          @impl Ltix.Property
          defdelegate parse(json, opts), to: Ltix.Claim

          defoverridable parse: 2
        end
    end
  end

  # Checks option values, which `use` receives as code. `:claim`, `:name`, and
  # `:strict` must be literals, and `:service` a module. A literal `:schema`
  # can't be a Zoi schema.
  defp check_values!(opts, caller) do
    for {key, value} <- opts, message = invalid(key, Macro.expand(value, caller)) do
      raise ArgumentError,
            "Ltix.Claim's #{inspect(key)} option #{message}, got #{Macro.to_string(value)}"
    end
  end

  defp invalid(:claim, value) when is_binary(value) and value != "", do: nil
  defp invalid(:claim, _value), do: "must be a non-empty string"
  defp invalid(:name, value) when is_atom(value), do: nil
  defp invalid(:name, _value), do: "must be an atom"
  defp invalid(:strict, value) when is_boolean(value), do: nil
  defp invalid(:strict, _value), do: "must be a boolean"
  defp invalid(:service, value) when is_atom(value) and value != nil, do: nil
  defp invalid(:service, _value), do: "must be a module"

  defp invalid(:schema, value),
    do: if(Macro.quoted_literal?(value), do: "must be a Zoi schema")

  defp invalid(_key, _value), do: nil
end
