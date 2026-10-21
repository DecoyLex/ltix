defmodule Ltix.Type do
  @moduledoc """
  A struct that converts to and from JSON, defined from Zoi schemas.

  Ltix's JSON structs, such as line items, content items, and object claims,
  are types. Convert any of them with `from_json/3` and `to_json/3`, and define
  your own type with `use Ltix.Type` and its fields as a keyword list of Zoi
  schemas. `use` defines the struct, its `t` type, and its enforced keys.

      defmodule MyLibrary.Badge do
        use Ltix.Type,
          fields: [
            id: Zoi.string(description: "The badge's ID."),
            label: Zoi.string(description: "The badge's label.") |> Zoi.optional()
          ]
      end

  Fields without `Zoi.optional/1` are enforced keys. Besides the standard
  fields, the struct has two more fields.

    * `:extensions` - property values, keyed by each property's name, as in
      `badge.extensions.color`. `new/2` takes them by name
    * `:unrecognized` - properties no field or property declares, keyed by
      their JSON names, as received. `from_json/3` fills it, and `to_json/3`
      sends it back unchanged

  ## Options

    * `:fields` - the standard fields, as a keyword list of Zoi schemas
      (required)
    * `:json_keys` - `:camel_case` to give each field the camelCase form of
      its name as its JSON name (defaults to `:field_name`)
    * `:metadata` - metadata for the struct's Zoi schema, read with
      `Zoi.metadata/1`

  ## JSON names

  A field's JSON name is the field name as a string, such as `"score_maximum"`
  for `score_maximum`. With `json_keys: :camel_case`, it's the camelCase form,
  such as `"scoreMaximum"`. Set another JSON name with `json_key:` metadata.

      line_items: Zoi.string(metadata: [json_key: "lineitems"]) |> Zoi.optional()

  Inside a field's value, the keys of a nested `Zoi.map/2` with declared
  fields, such as `Zoi.map(%{target_name: Zoi.string()})`, follow the same
  style and take `json_key:` too, alone or inside `Zoi.array/2` or
  `Zoi.nullable/2`. Other keys, such as those of
  `Zoi.map(Zoi.string(), Zoi.string())`, are sent as written.

  ## JSON values

  A field's schema checks the field's value in the struct. When the field's
  JSON value has another form, such as a date in an ISO 8601 string, give
  the field `from_json:` and `to_json:` in its schema's metadata.

      awarded_on:
        Zoi.date(metadata: [from_json: &Date.from_iso8601/1, to_json: &Date.to_iso8601/1])
        |> Zoi.optional()

    * `:from_json` - a function that takes the JSON value and returns
      `{:ok, value}` or `{:error, reason}`. `from_json/3` parses its value
      with the field's schema
    * `:to_json` - a function that takes the field's value and returns its
      JSON

  ## Properties

  Plugins can add properties to a type that also calls `use Ltix.Provider`.

      use Ltix.Provider, hook: [Ltix.Property]

  `from_json/3` and `to_json/3` parse and serialize each of the type's
  properties in a plugin set. Pass a property to `new/2` by its name, and read
  it from `extensions`, such as `badge.extensions.color`.
  """

  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Errors.Invalid.MissingClaim
  alias Ltix.Options
  alias Ltix.PluginSet
  alias Ltix.PluginSet.Entry
  alias Ltix.Property

  @json_keys [:field_name, :camel_case]

  defmacro __using__(opts) do
    fields = Keyword.fetch!(opts, :fields)
    json_keys = Keyword.get(opts, :json_keys, :field_name)

    unless json_keys in @json_keys do
      raise ArgumentError,
            "Ltix.Type's :json_keys option must be one of #{inspect(@json_keys)}, got #{inspect(json_keys)}"
    end

    schema =
      quote do
        @ltix_type_schema Zoi.struct(__MODULE__, unquote(fields),
                            coerce: true,
                            unrecognized_keys: :error,
                            empty_values: [nil],
                            metadata: unquote(Keyword.get(opts, :metadata, []))
                          )

        @ltix_type_json_keys unquote(json_keys)
      end

    struct =
      quote unquote: false do
        @type t :: unquote(Ltix.Type.__type_spec__(@ltix_type_schema))
        @enforce_keys Zoi.Struct.enforce_keys(@ltix_type_schema)
        defstruct Zoi.Struct.struct_fields(@ltix_type_schema) ++
                    [extensions: %{}, unrecognized: %{}]

        @ltix_type_json_fields Ltix.Type.__json_fields__(
                                 @ltix_type_schema,
                                 @ltix_type_json_keys
                               )

        @doc false
        def __ltix_type__(:schema), do: @ltix_type_schema
        def __ltix_type__(:json_fields), do: @ltix_type_json_fields
        def __ltix_type__(:json_keys), do: @ltix_type_json_keys
      end

    [schema, struct]
  end

  # Adds a Fields section that describes each field to the moduledoc, unless
  # the moduledoc is `false`. Object claims and content item types use it.
  @doc false
  defmacro __before_compile__(env) do
    case Module.get_attribute(env.module, :moduledoc) do
      {_line, false} ->
        nil

      moduledoc ->
        fields = Zoi.describe(Module.get_attribute(env.module, :ltix_type_schema))

        quote do
          @moduledoc unquote(moduledoc_text(moduledoc) <> "## Fields\n\n" <> fields)
        end
    end
  end

  defp moduledoc_text({_line, docs}) when is_binary(docs),
    do: String.trim_trailing(docs) <> "\n\n"

  defp moduledoc_text(nil), do: ""

  # Each field as `{field, json_key, schema, required?}`.
  @doc false
  def __json_fields__(schema, json_keys) do
    required = Zoi.Struct.enforce_keys(schema)

    for {field, field_schema} <- schema.fields do
      {field, json_name(field, field_schema, json_keys), field_schema, field in required}
    end
  end

  @doc false
  def __type_spec__(schema) do
    {:%, meta, [module, {:%{}, map_meta, fields}]} = Zoi.type_spec(schema)

    extra =
      quote do
        [
          extensions: %{optional(atom()) => term()},
          unrecognized: %{optional(String.t()) => term()}
        ]
      end

    {:%, meta, [module, {:%{}, map_meta, fields ++ extra}]}
  end

  @doc """
  Returns a type's standard fields as a keyword list of Zoi schemas, in
  declaration order.
  """
  @spec fields(module()) :: keyword(Zoi.schema())
  def fields(type), do: type.__ltix_type__(:schema).fields

  # A type's struct as a map of its standard fields, which `new/2` and the
  # type's own `new/1` take.
  @doc false
  def standard_fields(%type{} = value), do: Map.take(value, Keyword.keys(fields(type)))

  # The JSON names of a type's standard fields, or `[]` for a module that
  # isn't a type, such as a scalar claim.
  @doc false
  def json_names(module) do
    if type?(module),
      do: for({_field, key, _schema, _required?} <- module.__ltix_type__(:json_fields), do: key),
      else: []
  end

  # The names of a type's standard fields, or `[]` for a module that isn't a
  # type.
  @doc false
  def field_names(module), do: if(type?(module), do: Keyword.keys(fields(module)), else: [])

  defp type?(module), do: function_exported?(module, :__ltix_type__, 1)

  @doc """
  Returns a Zoi schema for a nested object with `fields`, given as a map of
  Zoi schemas. `opts` are Zoi options for the map, such as `description:`.

  The schema rejects unknown keys, and treats a key whose value is `nil` as
  omitted. Wrap it in `Zoi.optional/1` to make the field optional.

      iex> reviewer = Ltix.Type.object(%{name: Zoi.string()})
      iex> Zoi.parse(reviewer, %{name: "Ada"})
      {:ok, %{name: "Ada"}}
  """
  @spec object(map(), keyword()) :: Zoi.schema()
  def object(fields, opts \\ []) do
    Zoi.map(
      fields,
      Keyword.merge(opts,
        unrecognized_keys: :error,
        empty_values: [nil],
        error: "invalid type: expected a map or keyword list"
      )
    )
  end

  @doc """
  Builds a type's struct from its fields, given as a keyword list or a map.

  Nested values may be keyword lists, such as `window: [width: 400]`. A field
  given `nil` counts as omitted.

  The fields can include properties by name, and each property's value goes
  in `extensions`. Put the plugins that declare them in `fields` too, under
  the `:plugins` key, as a list such as `[MyPlugin]` or an `Ltix.PluginSet`.
  Without that key, `new/2` uses the configured plugins.

      {:ok, link} =
        Ltix.Type.new(Ltix.DeepLinking.ContentItem.LTIResourceLink,
          url: "https://tool.example.com/quizzes/7",
          weight: 2,
          plugins: [MyLibrary]
        )

      link.extensions.weight
      #=> 2

  A missing required field, a name that's neither a field nor a property,
  and an invalid value are `Ltix.Errors.Invalid.InvalidField` errors, and
  several are grouped in `Ltix.Errors.Invalid`. Returns
  `Ltix.Errors.Unknown.InvalidPluginSet` when the plugins conflict.
  """
  @spec new(module(), keyword() | map()) :: {:ok, struct()} | {:error, Exception.t()}
  def new(type, fields) when is_list(fields) or is_map(fields) do
    {plugins, fields} = Map.pop(Map.new(fields), :plugins)

    with {:ok, plugins} <- PluginSet.resolve(plugins),
         {extensions, fields} = split_properties(type, fields, plugins),
         input = Map.new(fields, fn {key, value} -> {key, Options.keyword_to_map(value)} end),
         {:ok, value} <- InvalidField.parse(type, type.__ltix_type__(:schema), input) do
      {:ok, %{value | extensions: extensions}}
    end
  end

  # Splits the names of a type's properties in a plugin set out of a map of
  # its fields. Returns the properties and the other fields.
  @doc false
  @spec split_properties(module(), map(), PluginSet.t()) :: {map(), map()}
  def split_properties(type, fields, %PluginSet{} = plugins) do
    names = for entry <- PluginSet.entries(plugins, type), do: entry.opts[:name]
    Map.split(fields, names)
  end

  @doc """
  Parses JSON into a type's struct.

  A missing or malformed field with `Zoi.optional/1` is left at its default,
  and a missing or malformed field without it is an error. Each of the type's
  properties in `:plugins` is parsed with its `c:Ltix.Property.parse/2` and
  goes in `extensions`, and a property that fails to parse is an error.
  Properties no field or property declares go in `unrecognized`. Returns
  `Ltix.Errors.Unknown.InvalidPluginSet` when the plugins conflict.

  ## Options

    * `:plugins` - the plugins to parse the type's properties with, as a
      list such as `[MyPlugin]` or an `Ltix.PluginSet`. Defaults to `nil`,
      which uses the configured plugins
    * `:name` - the name errors give the JSON, such as `"context"` for an
      error about `"context.id"`
  """
  @spec from_json(module(), term(), keyword()) :: {:ok, struct()} | {:error, Exception.t()}
  def from_json(type, json, opts \\ [])

  def from_json(type, json, opts) when is_map(json) do
    with {:ok, plugins} <- PluginSet.resolve(opts[:plugins]) do
      opts = Keyword.put(opts, :plugins, plugins)
      fields = type.__ltix_type__(:json_fields)
      properties = properties(type, plugins)
      {property_json, json} = Map.split(normalize_nulls(json), Map.keys(properties))

      {values, field_errors} = parse_fields(fields, json, opts)
      {extensions, property_errors} = parse_properties(properties, property_json, opts)
      unrecognized = Map.drop(json, for({_field, key, _schema, _required?} <- fields, do: key))

      with :ok <- Errors.collect(field_errors ++ property_errors) do
        {:ok, struct!(type, [extensions: extensions, unrecognized: unrecognized] ++ values)}
      end
    end
  end

  def from_json(_type, json, opts) do
    {:error,
     InvalidClaim.exception(claim: opts[:name], value: json, message: "must be an object")}
  end

  # Moves the type's properties in `plugins` from a parsed value's
  # `unrecognized` to its `extensions`, parsing each one with its
  # `c:Ltix.Property.parse/2`. Takes `from_json/3`'s `:name`.
  @doc false
  @spec parse_extensions(struct(), PluginSet.t(), keyword()) ::
          {:ok, struct()} | {:error, Exception.t()}
  def parse_extensions(%type{} = value, %PluginSet{} = plugins, opts) do
    properties = properties(type, plugins)
    {property_json, unrecognized} = Map.split(value.unrecognized, Map.keys(properties))
    {extensions, errors} = parse_properties(properties, property_json, opts)

    with :ok <- Errors.collect(errors) do
      {:ok,
       %{value | extensions: Map.merge(value.extensions, extensions), unrecognized: unrecognized}}
    end
  end

  # The type's properties in `plugins`, keyed by JSON name.
  defp properties(type, plugins) do
    for entry <- PluginSet.entries(plugins, type),
        into: %{},
        do: {entry.opts[:property], entry}
  end

  # Returns the parsed values of `fields`, given as
  # `{field, json_key, schema, required?}`, and the errors.
  defp parse_fields(fields, json, opts) do
    {values, errors} =
      Enum.reduce(fields, {[], []}, fn {field, key, schema, required?}, {values, errors} ->
        case parse_value(Map.fetch(json, key), field, schema, required?, opts) do
          :default -> {values, errors}
          {:ok, value} -> {[{field, value} | values], errors}
          {:error, error} -> {values, [error | errors]}
        end
      end)

    {values, Enum.reverse(errors)}
  end

  # Returns the extensions parsed from the JSON of `properties`, and the errors.
  defp parse_properties(properties, json, opts) do
    {extensions, errors} =
      Enum.reduce(json, {%{}, []}, fn
        {_key, nil}, parsed ->
          parsed

        {key, value}, {extensions, errors} ->
          %Entry{module: property, opts: property_opts} = Map.fetch!(properties, key)

          case property.parse(value, property_opts) do
            {:ok, extension} ->
              {Map.put(extensions, property_opts[:name], extension), errors}

            {:error, reason} ->
              error = Errors.from_reason(reason, value, path(key, opts))
              {extensions, [error | errors]}
          end
      end)

    {extensions, Enum.reverse(errors)}
  end

  @doc """
  Serializes a type's struct to JSON.

  The JSON includes unrecognized properties, standard fields, and each of the
  type's properties in `plugins` that the value has an extension for. Standard
  fields replace unrecognized properties of the same name, and declared
  properties replace both. Standard fields that are `nil` are left out, and so
  are `nil` values inside them. A field with `to_json:` in its schema's
  metadata is sent as that function returns it, and otherwise a `DateTime`
  becomes an ISO 8601 string.

  `operation` is the write operation the JSON is for, and a property whose
  [`:writes`](`m:Ltix.Property#module-options`) option excludes it is left
  out. `:read` includes every property, as a platform sends the type when it's
  read. `plugins` is a list of plugins such as `[MyPlugin]` or an
  `Ltix.PluginSet`, and defaults to `nil`, which uses the configured plugins.
  Raises `Ltix.Errors.Unknown.InvalidPluginSet` when the plugins conflict.
  """
  @spec to_json(
          struct(),
          PluginSet.enabled_plugins() | PluginSet.t() | nil,
          Property.write_operation() | :read
        ) :: map()
  def to_json(%type{} = value, plugins \\ nil, operation \\ :create) do
    plugins =
      case PluginSet.resolve(plugins) do
        {:ok, plugins} -> plugins
        {:error, error} -> raise error
      end

    json_keys = type.__ltix_type__(:json_keys)

    standard =
      for {field, key, schema, _required?} <- type.__ltix_type__(:json_fields),
          field_value <- [Map.fetch!(value, field)],
          field_value != nil,
          into: %{},
          do: {key, field_json(field_value, schema, json_keys)}

    properties =
      for %Entry{module: property, opts: opts} <- PluginSet.entries(plugins, type),
          operation == :read || operation in Keyword.get(opts, :writes, [:create, :update]),
          {:ok, extension} <- [Map.fetch(value.extensions, opts[:name])],
          into: %{},
          do: {opts[:property], property.serialize(extension, opts)}

    value.unrecognized
    |> Map.merge(standard)
    |> Map.merge(properties)
  end

  defp field_json(value, schema, json_keys) do
    case Zoi.metadata(schema)[:to_json] do
      nil -> json_value(value, schema, json_keys)
      to_json -> to_json.(value)
    end
  end

  # Serializes a value with its schema. The keys a nested map's schema
  # declares get JSON names, and other keys are sent as written.
  defp json_value(%DateTime{} = date_time, _schema, _json_keys),
    do: DateTime.to_iso8601(date_time)

  defp json_value(value, %Zoi.Types.Union{schemas: schemas}, json_keys),
    do: json_value(value, Enum.find(schemas, &shape?(value, &1)), json_keys)

  defp json_value(map, schema, json_keys) when is_map(map) and not is_struct(map) do
    for {key, value} <- map,
        value != nil,
        {json_key, member_schema} <- [member(schema, key, json_keys)],
        into: %{},
        do: {json_key, json_value(value, member_schema, json_keys)}
  end

  defp json_value(list, %Zoi.Types.Array{inner: inner}, json_keys) when is_list(list),
    do: Enum.map(list, &json_value(&1, inner, json_keys))

  defp json_value(list, _schema, json_keys) when is_list(list),
    do: Enum.map(list, &json_value(&1, nil, json_keys))

  defp json_value(value, _schema, _json_keys), do: value

  defp shape?(map, %Zoi.Types.Map{fields: fields}) when is_map(map), do: is_list(fields)
  defp shape?(list, %Zoi.Types.Array{}) when is_list(list), do: true
  defp shape?(_value, _schema), do: false

  # The JSON key and schema of a map's value at `key`.
  defp member(%Zoi.Types.Map{fields: fields}, key, json_keys) when is_list(fields) do
    case List.keyfind(fields, key, 0) do
      {_key, schema} -> {json_name(key, schema, json_keys), schema}
      nil -> {written_key(key), nil}
    end
  end

  defp member(%Zoi.Types.Map{value_type: value_type}, key, _json_keys),
    do: {written_key(key), value_type}

  defp member(_schema, key, _json_keys), do: {written_key(key), nil}

  defp json_name(field, schema, json_keys),
    do: Keyword.get(Zoi.metadata(schema), :json_key, json_key(field, json_keys))

  defp json_key(key, :camel_case) when is_atom(key), do: Recase.to_camel(Atom.to_string(key))
  defp json_key(key, _json_keys), do: written_key(key)

  defp written_key(key) when is_atom(key), do: Atom.to_string(key)
  defp written_key(key), do: key

  defp parse_value(:error, field, _schema, true, opts),
    do: {:error, MissingClaim.exception(claim: path(field, opts))}

  defp parse_value(:error, _field, _schema, false, _opts), do: :default
  defp parse_value({:ok, nil}, _field, _schema, false, _opts), do: :default

  defp parse_value({:ok, value}, field, schema, required?, opts) do
    case parse_json(value, schema) do
      {:ok, _value} = ok ->
        ok

      {:error, _reason} when not required? ->
        :default

      {:error, reason} ->
        {:error, Errors.from_reason(reason, value, path(field, opts))}
    end
  end

  defp parse_json(value, schema) do
    case Zoi.metadata(schema)[:from_json] do
      nil -> Zoi.parse(schema, value)
      from_json -> with {:ok, value} <- from_json.(value), do: Zoi.parse(schema, value)
    end
  end

  defp path(field, opts), do: Enum.join(Enum.reject([opts[:name], field], &is_nil/1), ".")

  # Some JSON libraries decode `null` as `:null`.
  defp normalize_nulls(:null), do: nil

  defp normalize_nulls(json) when is_map(json),
    do: Map.new(json, fn {k, v} -> {k, normalize_nulls(v)} end)

  defp normalize_nulls(json) when is_list(json), do: Enum.map(json, &normalize_nulls/1)
  defp normalize_nulls(json), do: json
end
