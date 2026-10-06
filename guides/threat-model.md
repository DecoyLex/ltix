# Threat Model

Ltix authenticates LTI launches and calls platform services for your tool. This guide covers who Ltix trusts, what it guarantees, and what is out of scope. A security report is a case where Ltix breaks one of these guarantees.

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
- **Expiry.** The token hasn't expired and was issued within the last hour, allowing a few seconds of clock skew. Change the hour with the `:max_token_age` option.
- **Browser.** The launch arrived in the browser that started the login, for the registration that login found. The token's nonce has to match the state your application kept from `Ltix.handle_login/3`.
- **Replay.** The nonce hasn't been used before, as long as your storage adapter records each nonce once.
- **Deployment.** Your storage adapter returned a deployment for the token's deployment ID.

When a token's key ID isn't in the cached key set, Ltix fetches the key set again only if the cached copy is at least 30 seconds old. Launches that arrive at the same time can each fetch it. A key set URL with no cached copy is fetched on every launch, which happens while fetches fail or when the platform sends `max-age=0`.

Ltix rejects input only when authenticating the launch or doing what you asked depends on it. A launch with a malformed optional field still succeeds, and that field is left out.

## Platform requests

Every request Ltix sends to a platform, for keys, tokens, or services, meets these rules.

- **Addresses.** Ltix connects only to public addresses. A request that would connect to a private network address or to your own machine returns `Ltix.Errors.Security.LocalNetworkAccessDenied`, whatever host name the URL uses. For a platform on your network or your machine, set `local_network_access: :local` or `:loopback` in your config or on the call.
- **HTTPS.** URLs have to be absolute HTTPS URLs without user information. HTTP is accepted only for loopback and local hosts. Disabling certificate verification returns an error.
- **Redirects.** Ltix follows a redirect only to the same scheme, host, and port.
- **Pagination.** Ltix follows a next page link only to the first page's origin, and returns an error when a link repeats a page.

Inspecting a `Ltix.JWK`, `Ltix.OAuth.AccessToken`, or `Ltix.OAuth.Client` hides the private key and the access token, so they stay out of logs and error reports.

## Your application

These guarantees depend on your application doing its part. It keeps the login state in the user's session, records each nonce once, protects the routes it serves after a launch, and keeps its signing keys secret. [Hardening Your Tool](hardening.md) covers each step.

## Out of scope

- A platform's own security, including a stolen platform signing key.
- An attacker who controls your application's server or its storage.
- Rate limiting your login and launch endpoints.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub's private vulnerability reporting on the [Ltix repository](https://github.com/DecoyLex/ltix/security), or by email to security@ltix.decoylex.com.

## Next steps

- [Hardening Your Tool](hardening.md): what your application has to do
- [Concepts](concepts.md): how a launch works
- [Storage Adapters](storage-adapters.md): the callbacks your application implements
