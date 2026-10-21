defmodule Ltix.Claim do
  @moduledoc """
  Declares a claim, which Ltix parses into a message's `claims`.

  Declare a vendor's claim, or any claim no other plugin declares, to read it by
  its short name, such as `launch.claims.tenant`. A declared claim is optional
  unless a [message type](`Ltix.Launch.MessageType`) requires it.

  ## Anonymous claims

  A claim whose value needs only a Zoi schema is an anonymous claim, which a
  plugin adds with `add/2`.

      Ltix.Plugin.new(name: "My Library")
      |> Ltix.Claim.add(
        claim: "https://lms.example.com/claim/tenant",
        name: :tenant,
        schema: Zoi.string()
      )

  Without `:schema`, the claim's value is its JSON value.

  ## Object claims

  A claim whose value is a JSON object lists its fields as Zoi schemas, and
  `use Ltix.Claim` defines a struct with those fields.

      defmodule MyLibrary.Session do
        @moduledoc "A platform's session for the launch."

        use Ltix.Claim,
          claim: "https://lms.example.com/claim/session",
          name: :session,
          fields: [
            id: Zoi.string(description: "The session's ID."),
            started_at: Zoi.integer(description: "When the session started.") |> Zoi.optional()
          ]
      end

  A malformed field with `Zoi.optional/1` is `nil`, and a missing or
  malformed field without it makes the claim malformed. Properties of the
  object that no field declares are in the struct's `unrecognized`.

  ## Claims that need code

  A claim module can implement `c:Ltix.Property.parse/2` to convert the value
  beyond what a Zoi schema does. `parse/2` receives the claim's options.

      defmodule MyLibrary.Tenant do
        use Ltix.Claim,
          claim: "https://lms.example.com/claim/tenant",
          name: :tenant

        @impl Ltix.Property
        def parse(value, _opts) do
          with {:ok, id} <- Zoi.parse(Zoi.string(), value), do: MyLibrary.Tenants.fetch(id)
        end
      end

  ## Options

  `add/2` and `use Ltix.Claim` take these options. A plugin can't add a claim
  module with an option its `use` sets.

    * `:claim` - the claim's URI, its key in the message's JSON (required)
    * `:name` - the claim's short name, its key in `claims` (required)
    * `:schema` - the Zoi schema that parses the claim's value. Without it, the
      value is the JSON value.
    * `:fields` - the fields of an object claim, as a keyword list of Zoi
      schemas. Only `use Ltix.Claim` takes it.
    * `:strict` - when `true`, a malformed value fails the launch or service
      call. When `false`, a malformed value is the claim's `:default` in
      `claims`, and the call continues (defaults to `true`).
    * `:default` - the value in `claims` when the message doesn't have the
      claim (defaults to `nil`)
    * `:service` - the service whose endpoint the claim has. Only
      `use Ltix.Claim` takes it.

  ## Endpoint claims

  A claim that has a service's endpoint sets `:service` to the service,
  declares `:fields`, and implements `c:new/1`. Its value is also the
  launch's endpoint for the service, which `Ltix.Launch.get_endpoint/2`
  returns.

      defmodule MyLibrary.AttendanceEndpoint do
        use Ltix.Claim,
          claim: "https://lms.example.com/claim/attendance",
          name: :attendance_endpoint,
          service: MyLibrary.AttendanceService,
          fields: [url: Zoi.string()]

        @impl Ltix.Claim
        def new(attributes), do: Ltix.Type.new(__MODULE__, attributes)
      end

  ## Conflicts

  Resolution fails with `Ltix.Errors.Unknown.InvalidPluginSet` when

    * two plugins declare the same claim URI, the same short name, or the
      endpoint of the same service
    * an endpoint claim lacks `:fields` or `c:new/1`

  A claim module added several times with the same options, or the same
  anonymous claim added several times, doesn't conflict.
  """
  use Ltix.Provider, hook: [Ltix.Property, Ltix.Claim.Declaration]

  alias Ltix.Options
  alias Ltix.Plugin
  alias Ltix.PluginSet.Entry

  # `Ltix.Claims` reports two entries that declare one claim.
  @impl Ltix.Provider
  def resolve(_plugins), do: {:ok, nil}

  @add_schema Zoi.keyword(
                [
                  claim:
                    Zoi.string(description: "The claim's URI, its key in the message's JSON.")
                    |> Zoi.min(1)
                    |> Zoi.required(),
                  name:
                    Zoi.atom(description: "The claim's short name, its key in `claims`.")
                    |> Zoi.required(),
                  schema:
                    Zoi.any(
                      description:
                        "The Zoi schema that parses the claim's value. Without it, the value is the JSON value."
                    )
                    |> Zoi.refine(&Ltix.Property.check_schema/1)
                    |> Zoi.optional(),
                  strict:
                    Zoi.boolean(
                      description:
                        "When `true`, a malformed value fails the launch or service call. When `false`, a malformed value is the claim's `:default` in `claims`, and the call continues."
                    )
                    |> Zoi.default(true),
                  default:
                    Zoi.any(
                      description:
                        "The value in `claims` when the message doesn't have the claim. Defaults to `nil`."
                    )
                    |> Zoi.optional()
                ],
                unrecognized_keys: :error
              )

  @doc """
  Builds an endpoint from its fields, given as a keyword list or a map, and
  checks it.

  Returns `{:error, exception}` for an endpoint the service can't call. Ltix
  also calls it with the fields of stored endpoints that an application passes
  to `Ltix.OAuth.Client`.
  """
  @callback new(attributes :: keyword() | map()) :: {:ok, struct()} | {:error, Exception.t()}

  @optional_callbacks new: 1

  @doc """
  Adds an anonymous claim to a plugin.

  Raises `Ltix.Errors.Invalid.InvalidOption` for a missing, unknown, or invalid
  option.

  ## Options

  #{Zoi.describe(@add_schema)}

  ## Examples

      iex> Ltix.Claim.add(
      ...>   Ltix.Plugin.new(),
      ...>   claim: "https://lms.example.com/claim/tenant",
      ...>   name: :tenant
      ...> )
      %Ltix.Plugin{
        entries: [
          %Ltix.PluginSet.Entry{
            module: Ltix.Claim,
            opts: [claim: "https://lms.example.com/claim/tenant", name: :tenant, strict: true]
          }
        ]
      }
  """
  @spec add(Plugin.t(), keyword()) :: Plugin.t()
  def add(%Plugin{} = plugin, opts) do
    opts = Options.parse!(opts, @add_schema)
    Plugin.add_entry(plugin, %Entry{module: __MODULE__, opts: opts})
  end

  # An anonymous claim parses its value with its `:schema` option.
  @doc false
  defdelegate parse(value, opts), to: Ltix.Property

  @doc false
  defdelegate serialize(value, opts), to: Ltix.Property
end
