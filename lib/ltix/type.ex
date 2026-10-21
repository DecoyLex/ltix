defmodule Ltix.Type do
  @moduledoc """
  A struct that converts to and from JSON, defined from Zoi schemas.

  Object claims are types. Convert one with `from_json/3` and `to_json/1`, and
  define your own type with `use Ltix.Type` and its fields as a keyword list of
  Zoi schemas. `use` defines the struct, its `t` type, and its enforced keys.

      defmodule MyLibrary.Badge do
        use Ltix.Type,
          fields: [
            id: Zoi.string(description: "The badge's ID."),
            label: Zoi.string(description: "The badge's label.") |> Zoi.optional()
          ]
      end

  Fields without `Zoi.optional/1` are enforced keys. Besides the standard
  fields, the struct has two more fields.

    * `:extensions` - property values, keyed by each property's name
    * `:unrecognized` - properties no field or property declares, keyed by
      their JSON names, as received. `from_json/3` fills it

  ## JSON names

  A field's JSON name is the field name as a string, such as `"score_maximum"`
  for `score_maximum`. Set another JSON name with `json_key:` metadata.

      line_items: Zoi.string(metadata: [json_key: "lineitems"]) |> Zoi.optional()
  """

  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidClaim
  alias Ltix.Errors.Invalid.MissingClaim

  defmacro __using__(opts) do
    fields = Keyword.fetch!(opts, :fields)

    schema =
      quote do
        @ltix_type_schema Zoi.struct(__MODULE__, unquote(fields), coerce: true)
      end

    struct =
      quote unquote: false do
        @type t :: unquote(Ltix.Type.__type_spec__(@ltix_type_schema))
        @enforce_keys Zoi.Struct.enforce_keys(@ltix_type_schema)
        defstruct Zoi.Struct.struct_fields(@ltix_type_schema) ++
                    [extensions: %{}, unrecognized: %{}]

        @ltix_type_json_fields Ltix.Type.__json_fields__(@ltix_type_schema)

        @doc false
        def __ltix_type__(:schema), do: @ltix_type_schema
        def __ltix_type__(:json_fields), do: @ltix_type_json_fields
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
  def __json_fields__(schema) do
    required = Zoi.Struct.enforce_keys(schema)

    for {field, field_schema} <- schema.fields do
      key = Keyword.get(Zoi.metadata(field_schema), :json_key, Atom.to_string(field))
      {field, key, field_schema, field in required}
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

  @doc """
  Parses JSON into a type's struct.

  A missing or malformed field with `Zoi.optional/1` is left at its default,
  and a missing or malformed field without it is an error. Properties no field
  declares go in `unrecognized`.

  ## Options

    * `:name` - the name errors give the JSON, such as `"context"` for an
      error about `"context.id"`
  """
  @spec from_json(module(), term(), keyword()) :: {:ok, struct()} | {:error, Exception.t()}
  def from_json(type, json, opts \\ [])

  def from_json(type, json, opts) when is_map(json) do
    with {:ok, values, unrecognized} <- parse_fields(type.__ltix_type__(:json_fields), json, opts),
         do: {:ok, struct!(type, [{:unrecognized, unrecognized} | values])}
  end

  def from_json(_type, json, opts) do
    {:error,
     InvalidClaim.exception(claim: opts[:name], value: json, message: "must be an object")}
  end

  # Parses the JSON of `fields`, given as `{field, json_key, schema, required?}`,
  # as `from_json/3` does. Returns the parsed values and the unrecognized
  # properties.
  @doc false
  @spec parse_fields([{atom(), String.t(), Zoi.schema(), boolean()}], map(), keyword()) ::
          {:ok, keyword(), map()} | {:error, Exception.t()}
  def parse_fields(fields, json, opts) do
    json = normalize_nulls(json)

    {values, errors} =
      Enum.reduce(fields, {[], []}, fn {field, key, schema, required?}, {values, errors} ->
        case parse_value(Map.fetch(json, key), field, schema, required?, opts) do
          :default -> {values, errors}
          {:ok, value} -> {[{field, value} | values], errors}
          {:error, error} -> {values, [error | errors]}
        end
      end)

    case errors do
      [] ->
        {:ok, values, Map.drop(json, for({_field, key, _schema, _required?} <- fields, do: key))}

      errors ->
        {:error, Errors.combine(Enum.reverse(errors))}
    end
  end

  @doc """
  Serializes a type's struct to JSON.

  Standard fields that are `nil` are left out. Unrecognized properties are
  included, and standard fields replace them.
  """
  @spec to_json(struct()) :: map()
  def to_json(%type{unrecognized: unrecognized} = value) do
    standard =
      for {field, key, _schema, _required?} <- type.__ltix_type__(:json_fields),
          field_value <- [Map.fetch!(value, field)],
          field_value != nil,
          into: %{},
          do: {key, field_value}

    Map.merge(unrecognized, standard)
  end

  defp parse_value(:error, field, _schema, true, opts),
    do: {:error, MissingClaim.exception(claim: path(field, opts))}

  defp parse_value(:error, _field, _schema, false, _opts), do: :default
  defp parse_value({:ok, nil}, _field, _schema, false, _opts), do: :default

  defp parse_value({:ok, value}, field, schema, required?, opts) do
    case Zoi.parse(schema, value) do
      {:ok, _value} = ok ->
        ok

      {:error, _errors} when not required? ->
        :default

      {:error, errors} ->
        {:error, Errors.from_zoi(errors, value, path(field, opts))}
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
