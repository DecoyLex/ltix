defmodule Ltix.DeepLinking.Response do
  @moduledoc """
  The signed response that `Ltix.DeepLinking.build_response/3` returns.

  Send it by posting `jwt` to `return_url` from a form that submits itself, as
  in this HEEx template.

  ```heex
  <form id="deep-link-response" method="post" action={@response.return_url}>
    <input type="hidden" name="JWT" value={@response.jwt} />
    <noscript>
      <button type="submit">Return to platform</button>
    </noscript>
  </form>
  <script>document.getElementById("deep-link-response").submit();</script>
  ```

  ## Fields

    * `:jwt` - the signed JWT
    * `:return_url` - the platform's `deep_link_return_url`

  ## Steps

  Response steps run during `Ltix.DeepLinking.build_response/3` and change the
  response's claims before it's signed. A module becomes a response step with
  `use Ltix.DeepLinking.Response`. A plugin adds it with `Ltix.Plugin.add/2`,
  or adds a function as a step with `add_step/2`.

  ```elixir
  defmodule MyApp.SelectionClaim do
    use Ltix.DeepLinking.Response

    @impl Ltix.Step
    def call(response, _opts) do
      {:ok, put_in(response.claims["https://tool.example.com/claim/selected_by"], "tool")}
    end
  end
  ```

  A step can change any claim, including the ones Ltix builds. When a step
  returns `{:error, exception}` or `{:halt, exception}`, the response isn't
  signed, and `Ltix.DeepLinking.build_response/3` returns the error.

  Steps also use these fields. `:jwt` is `nil` while steps run.

    * `:launch` - the `Ltix.Launch` of the Deep Linking request
    * `:claims` - the claims of the response JWT, keyed by claim name, such as
      `"https://purl.imsglobal.org/spec/lti-dl/claim/content_items"`
    * `:errors` - errors from steps (see `Ltix.Step`). A response that
      `Ltix.DeepLinking.build_response/3` returns has none.
    * `:plugins` - the `Ltix.PluginSet` the response is built with
  """
  # [DL, Deep linking response message](https://standards.1edtech.org/lti/specifications/launch_messages/deep_linking/lti-deep-linking-spec#deep-linking-response-message)
  use Ltix.Provider, hook: [Ltix.Step, Ltix.Ordered]

  defstruct [:launch, :plugins, :jwt, :return_url, claims: %{}, errors: []]

  @type t :: %__MODULE__{
          launch: Ltix.Launch.t() | nil,
          claims: %{String.t() => term()},
          errors: [Exception.t()],
          plugins: Ltix.PluginSet.t() | nil,
          jwt: String.t() | nil,
          return_url: String.t() | nil
        }

  @doc """
  Adds an anonymous response step to a plugin, a function that receives the
  response and returns what `c:Ltix.Step.call/2` returns.

  ```elixir
  Ltix.Plugin.new(name: "My Library")
  |> Ltix.DeepLinking.Response.add_step(fn response ->
    {:ok, put_in(response.claims["https://tool.example.com/claim/selected_by"], "tool")}
  end)
  ```

  Raises `ArgumentError` when `fun` doesn't take one argument.
  """
  @spec add_step(Ltix.Plugin.t(), (t() ->
                                     {:ok, t()} | {:error, Exception.t()} | {:halt, Exception.t()})) ::
          Ltix.Plugin.t()
  def add_step(plugin, fun), do: Ltix.Step.add(plugin, __MODULE__, fun)

  @doc """
  Calls `fun` with a plugin, and orders each response step that `fun` adds
  after `module`.

  [Order the steps a plugin adds](`m:Ltix.Ordered#module-order-the-steps-a-plugin-adds`)
  explains how the order applies. Raises `ArgumentError` when `fun` doesn't
  return the plugin it receives with only response steps added.
  """
  @spec run_after(Ltix.Plugin.t(), module(), (Ltix.Plugin.t() -> Ltix.Plugin.t())) ::
          Ltix.Plugin.t()
  def run_after(plugin, module, fun), do: Ltix.Ordered.run_after(plugin, __MODULE__, module, fun)

  @doc """
  Calls `fun` with a plugin, and orders each response step that `fun` adds
  before `module`.

  Works like `run_after/3`.
  """
  @spec run_before(Ltix.Plugin.t(), module(), (Ltix.Plugin.t() -> Ltix.Plugin.t())) ::
          Ltix.Plugin.t()
  def run_before(plugin, module, fun),
    do: Ltix.Ordered.run_before(plugin, __MODULE__, module, fun)
end
