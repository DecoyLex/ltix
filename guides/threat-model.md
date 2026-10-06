# Threat Model

Ltix authenticates LTI launches and calls platform services for your tool. This guide covers who Ltix trusts, what it protects against, and what your application has to do for the whole tool to be secure.

## Trust

Ltix follows the trust model of the LTI specifications. Registering a platform is the decision to trust it. After that, Ltix believes what the platform signs and what its services return, including the roles it assigns, the URLs in its launch claims, and the data in its responses.

Ltix also trusts your application's code and configuration, such as your storage adapter, claim parsers, role parsers, and options.

Everything else is untrusted.

| Party | Can | Can't |
|---|---|---|
| Anyone on the internet | Send any request to your login and launch endpoints | Produce a token signed by a registered platform |
| A user's browser | Change the requests it sends to your tool | Use another browser's login state |
| An attacker on the network | Observe and change unencrypted traffic | Read or change HTTPS traffic between your tool and a platform |
| A registered platform | Assert anything about its own users, courses, and deployments | Act as a different registration |

## Launches

A successful `Ltix.handle_callback/3` means all of the following hold.

- **Signature.** The ID token is signed with RS256 by a key from the registration's key set URL. Ltix rejects every other algorithm and any token with critical header extensions.
- **Registration.** The token's issuer and audience match a registration your storage adapter returned. A token whose audience includes any other client isn't accepted.
- **Expiry.** The token hasn't expired, allowing a few seconds of clock skew.
- **Browser.** The launch arrived in the browser that started the login, for the registration that login found. The token's nonce has to match the state your application kept from `Ltix.handle_login/3`.
- **Replay.** The nonce hasn't been used before, as long as your storage adapter consumes each nonce once.
- **Deployment.** Your storage adapter returned the deployment the token names.

An unknown key ID makes Ltix fetch the platform's key set again, at most once every 30 seconds for each key set URL. Requests with made-up key IDs can't make Ltix fetch on every launch.

Ltix rejects input only when authenticating the launch or doing what you asked depends on it. A launch with a malformed optional field still succeeds, and that field is left out.

## Platform requests

Every request Ltix sends to a platform, for keys, tokens, or services, meets these rules.

- **HTTPS.** URLs have to be absolute HTTPS URLs without user information. Disabling certificate verification returns an error.
- **Redirects.** Ltix follows a redirect only to the same scheme, host, and port.
- **Pagination.** Ltix follows a next page link only to the first page's origin, and returns an error when a link repeats a page.

Inspecting a `Ltix.JWK`, `Ltix.OAuth.AccessToken`, or `Ltix.OAuth.Client` hides the private key and the access token, so they stay out of logs and error reports.

## Your application's responsibilities

### Login state

Keep the state from `Ltix.handle_login/3` in the user's session and pass it to `Ltix.handle_callback/3`. Don't take it from the launch request. Launches usually arrive inside an iframe, so the session cookie needs `SameSite=None` and `Secure`. See [Getting Started](getting-started.md#iframe-strategy).

### Nonces

Your storage adapter's `c:Ltix.StorageAdapter.validate_nonce/2` has to consume each nonce exactly once, even when two launches arrive at the same moment. Expire stored nonces, because anyone who knows a registered issuer can start a login. `Ltix.Test.assert_storage_adapter!/2` checks that your adapter consumes each nonce once.

### After the launch

The checks above protect only the launch request. Protect the routes your tool serves afterward with your own CSRF tokens and session handling.

Decide what a user may do from the roles in `context.claims`, and take the course, resource link, and line items a user may act on from the verified launch. Don't accept them from later requests.

Claim values are platform data. Escape them when you render them.

### Redirects

`context.claims.target_link_uri` is where the platform wants the user to go. Check that it points to your tool before redirecting there.

### Keys and launch contexts

Keep your private key out of version control, logs, and responses. A `Ltix.LaunchContext` includes your registration and its private key, so keep contexts on the server and don't put them in a session cookie. See [JWK Management](jwk-management.md).

## Out of scope

- A platform's own security, including a stolen platform signing key.
- An attacker who controls your application's server or its storage.
- Rate limiting your login and launch endpoints.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub's private vulnerability reporting on the [Ltix repository](https://github.com/DecoyLex/ltix/security), or by email to security@ltix.decoylex.com.

## Next steps

- [Concepts](concepts.md): how a launch works
- [Storage Adapters](storage-adapters.md): the callbacks your application implements
- [Getting Started](getting-started.md): session and iframe setup
- [JWK Management](jwk-management.md): generating and rotating keys
