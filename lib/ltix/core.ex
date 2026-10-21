defmodule Ltix.Core do
  @moduledoc """
  The default [plugin](`Ltix.Plugin`) for LTI Core 1.3.0.

  It extends `Ltix.Login` with the default login steps, `Ltix.Launch` with the
  default launch steps, `Ltix.Claim` with Core's claims, and
  `Ltix.Launch.EveryMessageType` with `Ltix.Core.RequiredClaims`.

  ## Claims

  Every launch must have `version`, `deployment_id`, and `target_link_uri`.
  Each message type's module, such as `Ltix.ResourceLinkRequest`, lists the
  other claims a launch of that type must have. A malformed claim declared with
  `strict: false` is `nil`, its default, in `launch.claims` and stays in
  `launch.raw`. Any other malformed claim fails the launch.

  In `launch.raw`, LTI claims are keyed by URIs such as
  `https://purl.imsglobal.org/spec/lti/claim/roles`, and the others by the names
  in the first column. The Value column links the module of each claim that has
  one. The Strict column shows whether each claim's
  [`:strict`](`m:Ltix.Claim#module-options`) option is `true`.

  | Claim | Short name | Value | Strict |
  |---|---|---|---|
  | `iss` | `:issuer` | The platform's issuer, which Ltix checks is the registration's issuer | Yes |
  | `sub` | `:subject` | The user's subject identifier, a non-empty string. An anonymous launch has none. | Yes |
  | `aud` | `:audience` | The client ID the ID token is for, as a string or a list of strings. Ltix accepts only the registration's client ID. | Yes |
  | `exp` | `:expires_at` | When the ID token expires, in seconds since the Unix epoch. Ltix rejects a launch whose `exp` has passed. | Yes |
  | `iat` | `:issued_at` | When the platform issued the ID token, in seconds since the Unix epoch. Ltix rejects a launch older than [`:max_token_age`](`m:Ltix#module-configuration`) allows. | Yes |
  | `nonce` | `:nonce` | The single-use value from the tool's authentication request, which Ltix has verified and recorded as used | Yes |
  | `azp` | `:authorized_party` | The client ID the ID token was issued to. When it's present, Ltix rejects a launch whose `azp` isn't the registration's client ID. | Yes |
  | `email` | `:email` | The user's email address | No |
  | `name` | `:name` | The user's full name | No |
  | `given_name` | `:given_name` | The user's given name | No |
  | `family_name` | `:family_name` | The user's family name | No |
  | `middle_name` | `:middle_name` | The user's middle name | No |
  | `picture` | `:picture` | The URL of the user's picture | No |
  | `locale` | `:locale` | The user's preferred locale | No |
  | message type | `:message_type` | The kind of launch, such as `"LtiResourceLinkRequest"` | Yes |
  | LTI version | `:version` | `Ltix.Claims.Version` | Yes |
  | deployment ID | `:deployment_id` | The ID of the deployment the launch belongs to | Yes |
  | target link URI | `:target_link_uri` | The tool URL the launch ends at | Yes |
  | resource link | `:resource_link` | `Ltix.Claims.ResourceLink` | Yes |
  | roles | `:roles` | The user's role URIs in the context, or `[]`. Check them with `Ltix.Role`. | Yes |
  | context | `:context` | `Ltix.Claims.Context` | No |
  | platform instance | `:tool_platform` | `Ltix.Claims.ToolPlatform` | No |
  | launch presentation | `:launch_presentation` | `Ltix.Claims.LaunchPresentation` | No |
  | LIS | `:lis` | `Ltix.Claims.LIS` | No |
  | custom | `:custom` | The custom properties the platform set for the resource link, as a map with string keys | Yes |
  | role-scope mentor | `:role_scope_mentor` | `Ltix.Claims.RoleScopeMentor` | No |
  | organization | `:organization` | `Ltix.Claims.Organization` | No |
  | actual user | `:actual_user` | `Ltix.Claims.ActualUser` | No |

  ## Extending

  Every plugin set includes Core, so a plugin can extend these modules.

    * `Ltix.Login` to add login steps
    * `Ltix.Launch` to add launch steps
    * `Ltix.Claim` to declare claims
    * `Ltix.Launch.MessageType` to declare message types
    * `Ltix.ResourceLinkRequest` to change what resource link launches require
    * `Ltix.Launch.EveryMessageType` to change what every launch requires
    * `Ltix.ClientAssertion` to add client assertion steps
  """
  @behaviour Ltix.Plugin

  alias Ltix.Claim
  alias Ltix.Claims
  alias Ltix.ClientAssertion
  alias Ltix.Core.RequiredClaims
  alias Ltix.Launch
  alias Ltix.Login
  alias Ltix.Plugin
  alias Ltix.ResourceLinkRequest

  @version Mix.Project.config()[:version]

  # The launch steps, phases included, in the order they run. Listing them in
  # that order keeps that order when another plugin's step forms a cycle with
  # them, because a cycle runs in plugin order.
  @steps [
    Launch.CheckErrorResponse,
    Launch.ExtractIdToken,
    Launch.VerifyState,
    Launch.LookUpRegistration,
    Launch.VerifyIdToken,
    Launch.VerifyNonceBinding,
    Launch.ValidateNonce,
    Launch.Verified,
    Launch.ClaimsReceived,
    Launch.ParseClaims,
    Launch.ClaimsParsed,
    Launch.RejectUndeclaredMessageType,
    Launch.ValidateMessageType,
    Launch.Validated,
    Launch.LookUpDeployment,
    Launch.DeploymentFound
  ]

  # The launch steps that verify the message and look up its registration
  # and deployment. `Ltix.Test.build_launch/2` leaves them out, and sets the
  # test platform's deployment where Ltix looks it up.
  @security_steps [
    Launch.CheckErrorResponse,
    Launch.ExtractIdToken,
    Launch.VerifyState,
    Launch.LookUpRegistration,
    Launch.VerifyIdToken,
    Launch.VerifyNonceBinding,
    Launch.ValidateNonce,
    Launch.LookUpDeployment
  ]

  @lti "https://purl.imsglobal.org/spec/lti/claim/"

  # Core's claims that need only a Zoi schema.
  @anonymous_claims [
    # [Sec §5.1.2](https://www.imsglobal.org/spec/security/v1p0/#id-token)
    [claim: "iss", name: :issuer, schema: Zoi.string()],
    [claim: "sub", name: :subject, schema: Zoi.string() |> Zoi.min(1)],
    [claim: "aud", name: :audience, schema: Zoi.union([Zoi.string(), Zoi.list(Zoi.string())])],
    [claim: "exp", name: :expires_at, schema: Zoi.number()],
    [claim: "iat", name: :issued_at, schema: Zoi.number()],
    [claim: "nonce", name: :nonce, schema: Zoi.string()],
    [claim: "azp", name: :authorized_party, schema: Zoi.string()],
    # [Core §5.3.6](https://www.imsglobal.org/spec/lti/v1p3/#user-identity-claims)
    [claim: "email", name: :email, schema: Zoi.string(), strict: false],
    [claim: "name", name: :name, schema: Zoi.string(), strict: false],
    [claim: "given_name", name: :given_name, schema: Zoi.string(), strict: false],
    [claim: "family_name", name: :family_name, schema: Zoi.string(), strict: false],
    [claim: "middle_name", name: :middle_name, schema: Zoi.string(), strict: false],
    [claim: "picture", name: :picture, schema: Zoi.string(), strict: false],
    [claim: "locale", name: :locale, schema: Zoi.string(), strict: false],
    # [Core §5.3.1](https://www.imsglobal.org/spec/lti/v1p3/#message-type-claim)
    [claim: @lti <> "message_type", name: :message_type, schema: Zoi.string()],
    # [Core §5.3.3](https://www.imsglobal.org/spec/lti/v1p3/#lti-deployment-id-claim)
    [claim: @lti <> "deployment_id", name: :deployment_id, schema: Zoi.string() |> Zoi.min(1)],
    # [Core §5.3.4](https://www.imsglobal.org/spec/lti/v1p3/#target-link-uri)
    [
      claim: @lti <> "target_link_uri",
      name: :target_link_uri,
      schema: Zoi.string() |> Zoi.min(1)
    ],
    # [Core §5.3.7](https://www.imsglobal.org/spec/lti/v1p3/#roles-claim). Ltix 0.2 gave a
    # launch without roles `[]`.
    [claim: @lti <> "roles", name: :roles, schema: Zoi.list(Zoi.string()), default: []],
    # [Core §5.4.6](https://www.imsglobal.org/spec/lti/v1p3/#custom-properties-and-variable-substitution)
    [claim: @lti <> "custom", name: :custom]
  ]

  @claims [
    Claims.Version,
    Claims.ResourceLink,
    Claims.Context,
    Claims.ToolPlatform,
    Claims.LaunchPresentation,
    Claims.LIS,
    Claims.RoleScopeMentor,
    Claims.Organization,
    Claims.ActualUser
  ]

  @impl Ltix.Plugin
  def plugin(_opts) do
    [name: "LTI Core 1.3.0", version: @version]
    |> Plugin.new()
    |> add_login()
    |> add_providers()
    |> add_message_types()
    |> add_launch_steps()
    |> add_claims()
  end

  @doc false
  @spec security_steps() :: [module()]
  def security_steps, do: @security_steps

  defp add_login(plugin) do
    plugin
    |> Plugin.add(Login)
    |> Plugin.add(Login.CheckParameters)
    |> Plugin.add(Login.LookUpRegistration)
    |> Plugin.add(Login.RegistrationFound)
    |> Plugin.add(Login.BuildAuthenticationRequest)
  end

  defp add_providers(plugin) do
    plugin
    |> Plugin.add(Launch)
    |> Plugin.add(Claim)
    |> Plugin.add(Claims)
    |> Plugin.add(ClientAssertion)
    |> Plugin.add(Launch.MessageType)
    |> Plugin.add(Launch.EveryMessageType)
  end

  defp add_message_types(plugin) do
    plugin
    |> Plugin.add(ResourceLinkRequest)
    |> Plugin.add(RequiredClaims)
  end

  defp add_launch_steps(plugin), do: Enum.reduce(@steps, plugin, &Plugin.add(&2, &1))

  defp add_claims(plugin) do
    plugin = Enum.reduce(@claims, plugin, &Plugin.add(&2, &1))
    Enum.reduce(@anonymous_claims, plugin, &Claim.add(&2, &1))
  end
end
