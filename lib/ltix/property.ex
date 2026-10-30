defmodule Ltix.Property do
  @moduledoc """
  One JSON property, such as a claim or a line item field.

  Every property works the same way. Its options declare its JSON name and its
  Elixir name, `c:parse/2` reads its value from JSON, and `c:serialize/2`
  writes it back. A plugin adds a property to a type with the type's
  `add_property/2`.

  ```elixir
  Ltix.Plugin.new(name: "Polls")
  |> Ltix.DeepLinking.ContentItem.LTIResourceLink.add_property(
    property: "https://polls.example.com/weight",
    name: :poll_weight,
    schema: Zoi.integer()
  )
  ```

  Applications pass a property by its name wherever they build the type, and
  read it from the type's `extensions`, such as `link.extensions.poll_weight`.
  A claim is a property of the message, with `:claim` as its JSON name and
  `:name` as its key in `claims`.

  ## Properties that need code

  A property module calls `use` with the type's module and implements
  `c:parse/2` or `c:serialize/2`. Both receive the property's options.

  ```elixir
  defmodule Polls.Weight do
    use Ltix.DeepLinking.ContentItem.LTIResourceLink,
      property: "https://polls.example.com/weight",
      name: :poll_weight

    @impl Ltix.Property
    def serialize(weight, _opts), do: %{"value" => weight, "unit" => "points"}
  end
  ```

  For a value it can't parse, `c:parse/2` returns `{:error, reason}`, with a
  message, an exception, or the errors of `Zoi.parse/2` as the reason.

  ## Options

  `add_property/2` and the `use` of a property module take these options. A
  property module that extends several types sets them on its first `use`.

    * `:property` - the property's JSON name (required)
    * `:name` - the property's name, an atom (required)
    * `:schema` - the Zoi schema that parses the property's JSON value.
      Without it, the value is the JSON value.
    * `:writes` - the write operations whose JSON includes the property
      (defaults to `[:create, :update]`)
  """

  alias Ltix.Options
  alias Ltix.Plugin
  alias Ltix.PluginSet
  alias Ltix.PluginSet.Conflict
  alias Ltix.PluginSet.Entry
  alias Ltix.Provider

  # Names a property can't have, because types and their builders use them.
  @reserved_names [:extensions, :unrecognized, :plugins]

  @typedoc "Whether a type's JSON is for creating or updating it."
  @type write_operation :: :create | :update

  @doc """
  Parses the property's JSON value.

  Receives the property's options. The default parses the value with the
  `:schema` option, or returns it unchanged without one.
  """
  @callback parse(json :: term(), opts :: term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Serializes a parsed value back to JSON.

  Receives the property's options. The default returns the value unchanged.
  """
  @callback serialize(value :: term(), opts :: term()) :: term()

  defmacro __using__(opts) do
    check_options!(__CALLER__.module, opts)

    quote do
      require Ltix.Behaviour

      Ltix.Behaviour.declare_once Ltix.Property do
        @doc false
        def parse(json, opts), do: Ltix.Property.parse(json, opts)

        @doc false
        def serialize(value, opts), do: Ltix.Property.serialize(value, opts)

        defoverridable parse: 2, serialize: 2
      end
    end
  end

  # A claim's options are checked by `use Ltix.Claim`. A property module's
  # first `use` declares the property, and later ones may leave the options
  # out.
  defp check_options!(module, opts) do
    cond do
      Keyword.has_key?(opts, :claim) ->
        :ok

      Module.get_attribute(module, :ltix_property_declared) ->
        check_values!(opts)

      Keyword.has_key?(opts, :property) && Keyword.has_key?(opts, :name) ->
        Keyword.validate!(opts, [:property, :name, :schema, :writes])
        check_values!(opts)
        Module.put_attribute(module, :ltix_property_declared, true)

      true ->
        raise ArgumentError,
              "#{inspect(module)} requires the :property and :name options on its first `use` of a type"
    end
  end

  # Checks option values, which `use` receives as code. `:property`, `:name`,
  # and `:writes` must be literals. A literal `:schema` can't be a Zoi schema.
  defp check_values!(opts) do
    for {key, value} <- opts, message = invalid(key, value) do
      raise ArgumentError,
            "a property's #{inspect(key)} option #{message}, got #{Macro.to_string(value)}"
    end
  end

  defp invalid(:property, value) when is_binary(value) and value != "", do: nil
  defp invalid(:property, _value), do: "must be a non-empty string"
  defp invalid(:name, value) when is_atom(value), do: nil
  defp invalid(:name, _value), do: "must be an atom"

  defp invalid(:writes, value) do
    if is_list(value) && Enum.all?(value, &(&1 in [:create, :update])),
      do: nil,
      else: "must be a list of :create and :update"
  end

  defp invalid(:schema, value),
    do: if(Macro.quoted_literal?(value), do: "must be a Zoi schema")

  defp invalid(_key, _value), do: nil

  @options_schema Zoi.keyword(
                    [
                      property:
                        Zoi.string(description: "The property's JSON name.")
                        |> Zoi.min(1)
                        |> Zoi.required(),
                      name:
                        Zoi.atom(
                          description: "The property's name, its key in the type's `extensions`."
                        )
                        |> Zoi.required(),
                      schema:
                        Zoi.any(
                          description:
                            "The Zoi schema that parses the property's JSON value. Without it, the value is the JSON value."
                        )
                        |> Zoi.refine(&Ltix.Property.check_schema/1)
                        |> Zoi.optional(),
                      writes:
                        Zoi.list(Zoi.enum([:create, :update]),
                          description: "The write operations whose JSON includes the property."
                        )
                        |> Zoi.default([:create, :update])
                    ],
                    unrecognized_keys: :error
                  )

  @doc """
  Adds an anonymous property of `type` to a plugin.

  A type that plugins add properties to calls it from a function of its own,
  such as `Ltix.DeepLinking.ContentItem.Link.add_property/2`.

  ```elixir
  def add_property(plugin, opts), do: Ltix.Property.add(plugin, __MODULE__, opts)
  ```

  Raises `ArgumentError` when `type` isn't a type that takes properties, or for
  a missing, unknown, or invalid option.

  ## Options

  #{Zoi.describe(@options_schema)}

  ## Examples

  ```elixir
  iex> Ltix.Property.add(
  ...>   Ltix.Plugin.new(),
  ...>   Ltix.DeepLinking.ContentItem.Link,
  ...>   property: "https://polls.example.com/weight",
  ...>   name: :poll_weight
  ...> )
  %Ltix.Plugin{
    entries: [
      %Ltix.PluginSet.Entry{
        module: Ltix.Property,
        opts: [
          to: Ltix.DeepLinking.ContentItem.Link,
          property: "https://polls.example.com/weight",
          name: :poll_weight,
          writes: [:create, :update]
        ]
      }
    ]
  }
  ```
  """
  @spec add(Plugin.t(), module(), keyword()) :: Plugin.t()
  def add(%Plugin{} = plugin, type, opts) do
    unless Provider.hook?(type, __MODULE__) && function_exported?(type, :__ltix_type__, 1) do
      raise ArgumentError,
            "#{inspect(type)} doesn't take properties. It must call `use Ltix.Type`, " <>
              "and its `use Ltix.Provider` must include Ltix.Property in `:hook`."
    end

    opts = Options.parse!(opts, @options_schema)
    Plugin.add_entry(plugin, %Entry{module: __MODULE__, opts: [to: type] ++ opts})
  end

  # Returns the schema of `add/3`'s options, for the `add_property/2` docs of types.
  @doc false
  @spec options_schema() :: Zoi.schema()
  def options_schema, do: @options_schema

  @doc false
  @spec check_schema(term()) :: :ok | {:error, String.t()}
  def check_schema(schema) do
    if is_struct(schema) && Zoi.Type.impl_for(schema) != nil,
      do: :ok,
      else: {:error, "must be a Zoi schema"}
  end

  # Parses the value of an anonymous property, or of a property module that
  # doesn't implement `parse/2`, with its `:schema` option.
  @doc false
  @spec parse(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def parse(value, opts) do
    case Keyword.fetch(opts, :schema) do
      {:ok, schema} -> Zoi.parse(schema, value)
      :error -> {:ok, value}
    end
  end

  @doc false
  @spec serialize(term(), keyword()) :: term()
  def serialize(value, _opts), do: value

  @doc """
  Returns the conflicts of the properties a plugin set adds to a type.

  It returns one for each

    * JSON name or property name that several properties declare
    * property that declares a standard field's JSON name, a standard field's
      name, or a reserved property name (`:extensions`, `:unrecognized`, or
      `:plugins`)

  The default `c:Ltix.Provider.resolve/1` returns these conflicts for a type
  that plugins add properties to. A type that overrides `resolve/1` without
  calling `super/1` must call this function itself.

  ```elixir
  iex> {:ok, plugins} = Ltix.PluginSet.resolve([])
  iex> Ltix.Property.conflicts(plugins, Ltix.GradeService.LineItem)
  []
  ```
  """
  @spec conflicts(PluginSet.t(), module()) :: [Conflict.t()]
  def conflicts(%PluginSet{} = plugins, type) do
    properties = PluginSet.entries(plugins, type)
    json_names = Ltix.Type.json_names(type)
    fields = Ltix.Type.field_names(type)

    standard =
      for entry <- properties,
          {kind, value, taken} <- [
            {:property, entry.opts[:property], json_names},
            {:name, entry.opts[:name], fields}
          ],
          value in taken do
        %Conflict{
          parties: [entry],
          reason:
            "declares the #{kind} #{inspect(value)}, which is a standard field of #{inspect(type)}"
        }
      end

    reserved =
      for entry <- properties, entry.opts[:name] in @reserved_names do
        %Conflict{
          parties: [entry],
          reason: "declares the name #{inspect(entry.opts[:name])}, which Ltix reserves"
        }
      end

    by_property =
      Conflict.duplicates(
        properties,
        & &1.opts[:property],
        &"both declare the property #{inspect(&1)} on #{inspect(type)}"
      )

    # Properties that declare one JSON name and one property name conflict once.
    by_name =
      for conflict <-
            Conflict.duplicates(
              properties,
              & &1.opts[:name],
              &"both declare the name #{inspect(&1)} on #{inspect(type)}"
            ),
          !Enum.any?(by_property, &(&1.parties == conflict.parties)),
          do: conflict

    by_property ++ by_name ++ standard ++ reserved
  end
end
