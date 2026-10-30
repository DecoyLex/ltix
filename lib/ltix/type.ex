defmodule Ltix.Type do
  @moduledoc """
  A struct that converts to and from JSON, defined from Zoi schemas.

  Ltix's JSON structs, such as line items, content items, and object claims,
  are types. Convert any of them with `from_json/3` and `to_json/3`, and define
  your own type with `use Ltix.Type`.

      defmodule MyLibrary.Badge do
        use Ltix.Type,
          fields: [
            id: Zoi.string(description: "The badge's ID."),
            label: Zoi.string(description: "The badge's label.") |> Zoi.optional()
          ]
      end

  `use Ltix.Type` defines the struct and its `t` type. A field is optional when
  its schema has `Zoi.optional/1` or `Zoi.default/2`, and every other field is
  an enforced key. The struct also has these fields.

    * `:extensions` - property values, keyed by each property's name
    * `:unrecognized` - properties no field or plugin declares, keyed by JSON
      name

  ## Options

    * `:fields` - the standard fields, as a keyword list of Zoi schemas
      (required)
    * `:json_keys` - `:camel_case` for camelCase JSON names (defaults to
      `:field_name`)
    * `:metadata` - metadata for the struct's Zoi schema, read with
      `Zoi.metadata/1`
    * `:defaults` - default values in the struct, such as `[roles: []]`. A field
      with a default isn't an enforced key, and JSON must include it unless it's
      optional.

  ## JSON names

  A field's JSON name is the field name as a string, such as `"score_maximum"`
  for `score_maximum`. With `json_keys: :camel_case`, it's the camelCase form,
  such as `"scoreMaximum"`. Set another JSON name with `json_key:` metadata.

      line_items: Zoi.string(metadata: [json_key: "lineitems"]) |> Zoi.optional()

  The same rules apply to the keys of a nested map schema with declared fields,
  such as `Zoi.map(%{target_name: Zoi.string()})`, including one inside
  `Zoi.array/2` or `Zoi.nullable/2`. A map schema without declared fields, such
  as `Zoi.map(Zoi.string(), Zoi.string())`, uses its keys unchanged.

  For a field whose value is another type's struct, use `schema/2` as its
  schema.

  ## JSON values

  When a field's JSON differs from its value in the struct, such as a date in an
  ISO 8601 string, give its schema `from_json:` and `to_json:` metadata.

      awarded_on:
        Zoi.date(metadata: [from_json: &Date.from_iso8601/1, to_json: &Date.to_iso8601/1])
        |> Zoi.optional()

    * `:from_json` - a function that returns `{:ok, value}` or
      `{:error, reason}`. With arity 1 it takes the JSON value. With arity 2 it
      also takes `from_json/3`'s options, such as `:plugins`. The field's schema
      then checks the value.
    * `:to_json` - a function that takes the field's value and returns its JSON

  ## Malformed fields

  `from_json/3` sets a missing or malformed optional field to its default, and
  returns an error for any other missing or malformed field. When an optional
  field has `strict: true` metadata, a malformed value is an error.

      grade: Zoi.integer(metadata: [strict: true]) |> Zoi.optional()

  ## Properties

  Plugins can add properties to a type that also calls `use Ltix.Provider`.

      use Ltix.Provider, hook: [Ltix.Property]

  Pass a property to `new/3` by its name, and read it from `extensions`, such as
  `badge.extensions.color`.
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

  # How the schemas of a type's struct and of `object/2` parse their fields.
  @schema_options [coerce: true, unrecognized_keys: :error, empty_values: [nil]]

  @new_schema Zoi.keyword(
                [
                  schema:
                    Zoi.any(
                      description:
                        "A stricter struct schema to check the standard fields with, such as one that requires HTTPS URLs. Defaults to the type's schema."
                    )
                ],
                unrecognized_keys: :error
              )

  @from_json_schema Zoi.keyword(
                      [
                        plugins:
                          Zoi.any(
                            description:
                              "A list of plugins such as `[MyPlugin]`, or an `Ltix.PluginSet`, to parse properties with. Defaults to the configured plugins."
                          ),
                        name:
                          Zoi.string(
                            description:
                              "A prefix for the paths in errors, such as `\"context\"` for an error about `\"context.id\"`."
                          )
                      ],
                      unrecognized_keys: :error
                    )

  defmacro __using__(opts) do
    fields = Keyword.fetch!(opts, :fields)
    json_keys = Keyword.get(opts, :json_keys, :field_name)

    unless json_keys in @json_keys do
      raise ArgumentError,
            "Ltix.Type's :json_keys option must be one of #{inspect(@json_keys)}, got #{inspect(json_keys)}"
    end

    schema =
      quote do
        @ltix_type_schema Zoi.struct(
                            __MODULE__,
                            unquote(fields),
                            unquote(@schema_options) ++
                              [metadata: unquote(Keyword.get(opts, :metadata, []))]
                          )

        @ltix_type_json_keys unquote(json_keys)
        @ltix_type_defaults unquote(Keyword.get(opts, :defaults, []))
      end

    struct =
      quote unquote: false do
        @type t :: unquote(Ltix.Type.__type_spec__(@ltix_type_schema))
        @enforce_keys Zoi.Struct.enforce_keys(@ltix_type_schema) --
                        Keyword.keys(@ltix_type_defaults)
        defstruct Ltix.Type.__struct_fields__(@ltix_type_schema, @ltix_type_defaults) ++
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

    {:struct, _module, fields} = zoi_shape(schema)

    for {field, field_schema} <- fields do
      {field, json_name(field, field_schema, json_keys), field_schema, field in required}
    end
  end

  @doc false
  def __struct_fields__(schema, defaults) do
    for field <- Zoi.Struct.struct_fields(schema) do
      case field do
        {key, default} -> {key, Keyword.get(defaults, key, default)}
        key -> {key, Keyword.get(defaults, key)}
      end
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

  # A type's struct as a map of its standard fields, which `new/3` and the
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

  @doc """
  Returns a type's standard fields as a keyword list of Zoi schemas, in
  declaration order.

      iex> Keyword.keys(Ltix.Type.fields(Ltix.DeepLinking.LineItem))
      [:score_maximum, :label, :resource_id, :tag, :grades_released]
  """
  @spec fields(module()) :: keyword(Zoi.schema())
  def fields(type) do
    {:struct, _module, fields} = zoi_shape(type.__ltix_type__(:schema))
    fields
  end

  @doc """
  Returns a Zoi schema for a field whose value is a type's struct.

  With this schema, `new/3` accepts the field's value as the struct, or as its
  standard fields in a keyword list or map. `to_json/3` serializes the struct as
  that type's JSON. Zoi options, such as `description:`, are passed to the
  schema.

      grade: Ltix.Type.schema(MyLibrary.Grade, description: "The grade.") |> Zoi.optional()

      iex> schema = Ltix.Type.schema(Ltix.DeepLinking.LineItem)
      iex> {:ok, line_item} = Zoi.parse(schema, %{label: "Quiz 1", score_maximum: 10})
      iex> line_item.label
      "Quiz 1"
  """
  @spec schema(module(), keyword()) :: Zoi.schema()
  def schema(type, zoi_options \\ []),
    do: Zoi.struct(type, fields(type), @schema_options ++ zoi_options)

  @doc """
  Returns a Zoi schema for a nested object with `fields`, given as a map of
  Zoi schemas. `zoi_options` are Zoi options for the map, such as `description:`.

  The schema rejects unknown keys, and treats a key whose value is `nil` as
  omitted. Wrap it in `Zoi.optional/1` to make the field optional.

      iex> reviewer = Ltix.Type.object(%{name: Zoi.string()})
      iex> Zoi.parse(reviewer, %{name: "Ada"})
      {:ok, %{name: "Ada"}}
  """
  @spec object(map(), keyword()) :: Zoi.schema()
  def object(fields, zoi_options \\ []) do
    Zoi.map(
      fields,
      Keyword.merge(
        zoi_options,
        @schema_options ++ [error: "must be a map or keyword list"]
      )
    )
  end

  @doc """
  Builds a type's struct from its fields, given as a keyword list or a map.

  Nested values may be keyword lists, such as `window: [width: 400]`. A field
  given `nil` is the same as a field left out. `new/3` leaves the
  `:extensions` and `:unrecognized` of a nested type given as a struct
  unchanged.

  The fields can include properties by name, and a nested type's fields can
  include that type's properties. `new/3` puts each property's value in its
  type's `extensions`. Put the plugins that declare them in `fields` too, under the
  `:plugins` key, as a list such as `[MyPlugin]` or an `Ltix.PluginSet`.
  Without that key, `new/3` uses the configured plugins.

      {:ok, link} =
        Ltix.Type.new(Ltix.DeepLinking.ContentItem.LTIResourceLink,
          url: "https://tool.example.com/quizzes/7",
          weight: 2,
          plugins: [MyLibrary]
        )

      link.extensions.weight
      #=> 2

  Returns `Ltix.Errors.Invalid.InvalidField` for a missing required field, a
  name that's neither a field nor a property, or an invalid value. With
  several errors, it returns an `Ltix.Errors.Invalid` with one for each. Returns
  `Ltix.Errors.Unknown.InvalidPluginSet` when the plugins conflict.

      iex> {:ok, line_item} =
      ...>   Ltix.Type.new(Ltix.DeepLinking.LineItem, label: "Quiz 1", score_maximum: 10)
      iex> {line_item.label, line_item.score_maximum}
      {"Quiz 1", 10}

  ## Options

  #{Zoi.describe(@new_schema)}
  """
  @spec new(module(), keyword() | map(), keyword()) :: {:ok, struct()} | {:error, Exception.t()}
  def new(type, fields, opts \\ []) when is_list(fields) or is_map(fields) do
    opts = Options.parse!(opts, @new_schema)
    {plugins, fields} = Map.pop(Map.new(fields), :plugins)

    schema = Keyword.get_lazy(opts, :schema, fn -> type.__ltix_type__(:schema) end)

    schemas = fields(type)

    with {:ok, plugins} <- PluginSet.resolve(plugins),
         {extensions, fields} = split_properties(type, fields, plugins),
         inputs =
           Map.new(fields, fn {key, value} -> {key, input(value, schemas[key], plugins)} end),
         input = Map.new(inputs, fn {key, {value, _kept}} -> {key, value} end),
         {:ok, value} <- InvalidField.parse(type, schema, input) do
      {:ok, %{put_nested(value, inputs) | extensions: extensions}}
    end
  end

  # Puts back the extensions and unrecognized properties of nested types.
  defp put_nested(value, inputs) do
    Enum.reduce(inputs, value, fn
      {_key, {_input, nil}}, value -> value
      {key, {_input, kept}}, value -> Map.update!(value, key, &struct!(&1, kept))
    end)
  end

  # Returns a field's input for the type's schema, and the extensions and
  # unrecognized properties of a nested type, which the schema leaves out. A
  # field whose schema is another type's `schema/2` takes that type's struct,
  # or its standard fields and property names. A field whose schema is an
  # object or a map takes a keyword list as a map.
  defp input(value, nil, _plugins), do: {value, nil}
  defp input(value, schema, plugins), do: shaped_input(value, zoi_shape(schema), plugins)

  defp shaped_input(%_type{} = value, {:struct, _module, [_ | _]}, _plugins),
    do: {standard_fields(value), Map.take(value, [:extensions, :unrecognized])}

  defp shaped_input(value, {:struct, module, [_ | _]}, plugins) do
    case Options.keyword_to_map(value) do
      fields when is_map(fields) ->
        {extensions, fields} = split_properties(module, fields, plugins)
        {fields, %{extensions: extensions}}

      value ->
        {value, nil}
    end
  end

  defp shaped_input(value, {kind, _fields}, _plugins) when kind in [:object, :map],
    do: {Options.keyword_to_map(value), nil}

  defp shaped_input(value, _shape, _plugins), do: {value, nil}

  # Splits the names of a type's properties in a plugin set out of a map of
  # its fields. Returns the properties and the other fields.
  @doc false
  @spec split_properties(module(), map(), PluginSet.t()) :: {map(), map()}
  def split_properties(type, fields, %PluginSet{} = plugins) do
    names = for entry <- PluginSet.entries(plugins, type), do: entry.opts[:name]
    Map.split(fields, names)
  end

  defp type?(module), do: function_exported?(module, :__ltix_type__, 1)

  @doc """
  Parses JSON into a type's struct.

  See [Malformed fields](`m:Ltix.Type#module-malformed-fields`) for missing and
  malformed fields. For each property a plugin in `:plugins` declares,
  `from_json/3` parses its JSON value with the property's
  `c:Ltix.Property.parse/2` and puts the result in `extensions` under the
  property name. It puts JSON keys that match no standard field or declared
  property in `unrecognized`.

  When `parse/2` returns `{:error, reason}` and `reason` is an Ltix exception,
  `from_json/3` returns `{:error, reason}`. It converts a message or another
  exception to an `Ltix.Errors.Invalid.InvalidClaim` at the property's path,
  with its message. It converts `Zoi.parse/2` errors for missing keys to
  `Ltix.Errors.Invalid.MissingClaim`, and the rest to `InvalidClaim`, each at
  its path inside the property. It returns several errors grouped in one
  `Ltix.Errors.Invalid`.

  Returns `{:error, %Ltix.Errors.Unknown.InvalidPluginSet{}}` when the plugins
  [conflict](writing-plugins.md#fix-a-plugin-set-that-fails-to-resolve).
  Raises `ArgumentError` when `:plugins` has a module that isn't a plugin.

      iex> {:ok, line_item} =
      ...>   Ltix.Type.from_json(Ltix.DeepLinking.LineItem, %{
      ...>     "label" => "Quiz 1",
      ...>     "scoreMaximum" => 10,
      ...>     "https://lms.example.com/weight" => 2
      ...>   })
      iex> {line_item.label, line_item.unrecognized}
      {"Quiz 1", %{"https://lms.example.com/weight" => 2}}

  ## Options

  #{Zoi.describe(@from_json_schema)}
  """
  @spec from_json(module(), term(), keyword()) :: {:ok, struct()} | {:error, Exception.t()}
  def from_json(type, json, opts \\ []),
    do: parse_json(type, json, Options.parse!(opts, @from_json_schema))

  defp parse_json(type, json, opts) when is_map(json) do
    with {:ok, plugins} <- PluginSet.resolve(opts[:plugins]) do
      opts = Keyword.put(opts, :plugins, plugins)
      properties = properties(type, plugins)
      {property_json, json} = Map.split(normalize_nulls(json), Map.keys(properties))

      {values, field_errors} = parse_fields(type.__ltix_type__(:json_fields), json, opts)
      {extensions, property_errors} = parse_properties(properties, property_json, opts)

      with :ok <- Errors.collect(field_errors ++ property_errors) do
        unrecognized = Map.drop(json, json_names(type))
        {:ok, struct!(type, [extensions: extensions, unrecognized: unrecognized] ++ values)}
      end
    end
  end

  defp parse_json(_type, json, opts) do
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

  The JSON has the standard fields and the keys in `unrecognized`. `to_json/3`
  serializes each value in `extensions` with its property's
  `c:Ltix.Property.serialize/2`, under the property's JSON name. Standard
  fields and extensions replace unrecognized properties with the same JSON
  name. It leaves out standard fields that are `nil`, and `nil` values inside
  them. It writes a `DateTime` as an ISO 8601 string unless its field has
  [`to_json:` metadata](`m:Ltix.Type#module-json-values`).

  `plugins` is a list of plugins such as `[MyPlugin]` or an `Ltix.PluginSet`, and
  defaults to `nil`, which uses the configured plugins. It leaves out an
  extension when no plugin in `plugins` declares its property.

  `operation` is `:create` or `:update`, and defaults to `:create`. It leaves
  out an extension whose property's
  [`:writes`](`m:Ltix.Property#module-options`) option excludes the operation.

  Raises `Ltix.Errors.Unknown.InvalidPluginSet` when the plugins
  [conflict](writing-plugins.md#fix-a-plugin-set-that-fails-to-resolve), and
  `ArgumentError` when `plugins` has a module that isn't a plugin.

      iex> {:ok, line_item} =
      ...>   Ltix.Type.new(Ltix.DeepLinking.LineItem, label: "Quiz 1", score_maximum: 10)
      iex> Ltix.Type.to_json(line_item)
      %{"label" => "Quiz 1", "scoreMaximum" => 10}
  """
  @spec to_json(
          struct(),
          PluginSet.enabled_plugins() | PluginSet.t() | nil,
          Property.write_operation()
        ) ::
          map()
  def to_json(%type{} = value, plugins \\ nil, operation \\ :create) do
    plugins =
      case PluginSet.resolve(plugins) do
        {:ok, plugins} -> plugins
        {:error, error} -> raise error
      end

    serializing = %{
      json_keys: type.__ltix_type__(:json_keys),
      plugins: plugins,
      operation: operation
    }

    standard =
      for {field, key, schema, _required?} <- type.__ltix_type__(:json_fields),
          field_value <- [Map.fetch!(value, field)],
          field_value != nil,
          into: %{},
          do: {key, field_json(field_value, schema, serializing)}

    properties =
      for {property, %Entry{module: module, opts: opts}} <- properties(type, plugins),
          operation in Keyword.get(opts, :writes, [:create, :update]),
          {:ok, extension} <- [Map.fetch(value.extensions, opts[:name])],
          into: %{},
          do: {property, module.serialize(extension, opts)}

    value.unrecognized
    |> Map.merge(standard)
    |> Map.merge(properties)
  end

  defp field_json(value, schema, serializing) do
    case Zoi.metadata(schema)[:to_json] do
      nil -> json_value(value, zoi_shape(schema), serializing)
      to_json -> to_json.(value)
    end
  end

  # Serializes a value with the shape of its schema. The keys a nested
  # object's schema declares get JSON names, and other keys are sent as
  # written. A nested type is serialized with the plugin set and operation.
  defp json_value(%DateTime{} = date_time, _shape, _serializing),
    do: DateTime.to_iso8601(date_time)

  defp json_value(%type{} = value, _shape, serializing) do
    if type?(type),
      do: to_json(value, serializing.plugins, serializing.operation),
      else: value
  end

  defp json_value(value, {:union, schemas}, serializing) do
    shape =
      schemas
      |> Enum.map(&zoi_shape/1)
      |> Enum.find(:other, &fits?(value, &1))

    json_value(value, shape, serializing)
  end

  defp json_value(map, shape, serializing) when is_map(map) do
    for {key, value} <- map,
        value != nil,
        {json_key, value_shape} <- [member(shape, key, serializing.json_keys)],
        into: %{},
        do: {json_key, json_value(value, value_shape, serializing)}
  end

  defp json_value(list, {:array, item}, serializing) when is_list(list),
    do: Enum.map(list, &json_value(&1, zoi_shape(item), serializing))

  defp json_value(list, _shape, serializing) when is_list(list),
    do: Enum.map(list, &json_value(&1, :other, serializing))

  defp json_value(value, _shape, _serializing), do: value

  defp fits?(map, {:object, _fields}) when is_map(map), do: true
  defp fits?(list, {:array, _item}) when is_list(list), do: true
  defp fits?(_value, _shape), do: false

  # The JSON key and the shape of a map's value at `key`.
  defp member({:object, fields}, key, json_keys) do
    case List.keyfind(fields, key, 0) do
      {_key, schema} -> {json_name(key, schema, json_keys), zoi_shape(schema)}
      nil -> {key_as_written(key), :other}
    end
  end

  defp member({:map, value_schema}, key, _json_keys),
    do: {key_as_written(key), zoi_shape(value_schema)}

  defp member(_shape, key, _json_keys), do: {key_as_written(key), :other}

  # A field's or a nested key's JSON name, from its schema's `json_key:` or
  # the type's `:json_keys` style.
  defp json_name(key, schema, json_keys),
    do: Keyword.get(Zoi.metadata(schema), :json_key, styled_key(key, json_keys))

  defp styled_key(key, :camel_case) when is_atom(key), do: Recase.to_camel(Atom.to_string(key))
  defp styled_key(key, _json_keys), do: key_as_written(key)

  defp key_as_written(key) when is_atom(key), do: Atom.to_string(key)
  defp key_as_written(key), do: key

  # Zoi has no public API for the parts of a schema, so this function reads
  # Zoi's structs. It's the only code in Ltix that does, and returns
  # `{:struct, module, fields}`, `{:object, fields}` for a map with declared fields,
  # `{:map, value_schema}` for a map with any keys, `{:array, item_schema}`,
  # `{:union, schemas}`, or `:other`.
  defp zoi_shape(%Zoi.Types.Struct{module: module, fields: fields}), do: {:struct, module, fields}
  defp zoi_shape(%Zoi.Types.Map{fields: fields}) when is_list(fields), do: {:object, fields}
  defp zoi_shape(%Zoi.Types.Map{value_type: value_schema}), do: {:map, value_schema}
  defp zoi_shape(%Zoi.Types.Array{inner: item_schema}), do: {:array, item_schema}
  defp zoi_shape(%Zoi.Types.Union{schemas: schemas}), do: {:union, schemas}
  defp zoi_shape(_schema), do: :other

  defp parse_value(:error, field, _schema, true, opts),
    do: {:error, MissingClaim.exception(claim: path(field, opts))}

  defp parse_value(:error, _field, _schema, false, _opts), do: :default
  defp parse_value({:ok, nil}, _field, _schema, false, _opts), do: :default

  defp parse_value({:ok, value}, field, schema, required?, opts) do
    metadata = Zoi.metadata(schema)
    strict? = required? || Keyword.get(metadata, :strict, false)

    case parse_json(value, schema, metadata, opts) do
      {:ok, _value} = ok ->
        ok

      {:error, reason} when strict? ->
        {:error, Errors.from_reason(reason, value, path(field, opts))}

      {:error, _reason} ->
        :default
    end
  end

  defp parse_json(value, schema, metadata, opts) do
    with {:ok, value} <- json_to_value(value, metadata[:from_json], opts),
         do: Zoi.parse(schema, value)
  end

  defp json_to_value(value, nil, _opts), do: {:ok, value}

  defp json_to_value(value, from_json, opts) when is_function(from_json, 2),
    do: from_json.(value, opts)

  defp json_to_value(value, from_json, _opts), do: from_json.(value)

  defp path(field, opts), do: Enum.join(Enum.reject([opts[:name], field], &is_nil/1), ".")

  # Some JSON libraries decode `null` as `:null`.
  defp normalize_nulls(:null), do: nil

  defp normalize_nulls(json) when is_map(json),
    do: Map.new(json, fn {k, v} -> {k, normalize_nulls(v)} end)

  defp normalize_nulls(json) when is_list(json), do: Enum.map(json, &normalize_nulls/1)
  defp normalize_nulls(json), do: json
end
