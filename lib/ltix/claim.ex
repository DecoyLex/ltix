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

  `Ltix.Type.from_json/3` parses the fields, and a field error makes the claim
  malformed.

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

  ## Properties

  Plugins add properties to object claims, as `Ltix.Property` describes, such
  as with `Ltix.Claims.LaunchPresentation.add_property/2`. Read a property from
  the claim's `extensions` by its name.

      launch.claims.launch_presentation.extensions.placement
      #=> ["ContentArea"]

  [Add a property to a claim](writing-claim-and-launch-plugins.md#add-a-property-to-a-claim)
  shows an example.

  A property value that fails to parse makes the claim malformed.

  ## Checks

  A claim implements `c:check/2` to check its value against the message's other
  claims. Checks run after every claim is parsed. Other claims are keyed by
  short name, such as `:issued_at` for `iat` (see `Ltix.Core`).

      @impl Ltix.Claim
      def check(%MyLibrary.Session{started_at: started_at}, %{issued_at: issued_at})
          when is_integer(started_at) and started_at > issued_at,
          do: {:error, "must not be after the message was issued"}

      def check(_session, _claims), do: :ok

  Other plugins add checks with `Ltix.Claims.Check`, and replace a check in the
  message types they list with `Ltix.Claims.Override`. A malformed claim isn't
  checked.

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
    * two properties of an object claim declare the same JSON name or property
      name
    * a property of an object claim declares a standard field's JSON name or
      name, or a property name Ltix reserves (`:extensions`, `:unrecognized`,
      or `:plugins`)
    * an `Ltix.Claims.Check` checks a claim no plugin declares
    * two overrides replace the same check in one message type

  A claim, property, check, or override added several times with the same
  options doesn't conflict.
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
  Builds an endpoint from its fields and property names, given as a keyword
  list or a map, and validates it.

  Returns `{:error, exception}` for an endpoint the service can't call. Ltix
  also calls it with the fields of stored endpoints that an application passes
  to `Ltix.OAuth.Client`.
  """
  @callback new(attributes :: keyword() | map()) :: {:ok, struct()} | {:error, Exception.t()}

  @doc """
  Checks the claim's parsed value.

  Receives the value and every parsed claim. Returns `:ok`, or
  `{:error, reason}` with a message, an exception, or Zoi errors as the reason.
  """
  @callback check(value :: term(), claims :: %{atom() => term()}) :: :ok | {:error, term()}

  @optional_callbacks new: 1, check: 2

  @doc """
  Adds an anonymous claim to a plugin.

  Raises `ArgumentError` for a missing, unknown, or invalid option.

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
