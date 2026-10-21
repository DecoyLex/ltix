# Ltix

Ltix is an Elixir library for the tool side of LTI 1.3 and LTI Advantage. Its own features ship as plugins, and other libraries extend it with plugins of their own.

## LTI

### Specifications

**LTI**. Learning Tools Interoperability, the 1EdTech standard for integrating learning applications into educational platforms.

**LTI Advantage**. Core together with Deep Linking, AGS, and NRPS.

**Specification**. One document within a 1EdTech standard, such as Core 1.3.0, Deep Linking 2.0, AGS 2.0, or NRPS 2.0. _Avoid_ standard, protocol.

**Core**. The LTI Core specification. _Avoid_ using "core" for Ltix's own internals.

**LIS**. Learning Information Services, the 1EdTech standard that defines the role vocabularies and the course and person identifiers in the `lis` claim.

### Parties

**Platform**. The system a user works in, traditionally a learning management system such as Canvas or Moodle, that delegates functionality to tools. _Avoid_ LMS, tool consumer, tool platform.

**Tool**. An application or service outside a platform that provides functionality to it. Ltix implements the tool side. _Avoid_ tool provider, consumer.

**Vendor**. A platform maker that adds claims or properties no specification defines, such as Instructure for Canvas.

**Platform instance**. One installation of a platform, such as a university's Canvas site, described by the `tool_platform` claim.

**Organization**. The institution that supports a context, described by the `organization` claim. _Avoid_ using "organization" for a context.

### Registration and deployment

**Registration**. The security contract a tool and a platform establish out of band, in which the platform issues a client ID and the two exchange keys and the URLs each side needs. A registration is identified by issuer and client ID.

**Issuer**. The party that signs a message. A platform's issuer is an HTTPS URL with no query or fragment, and a tool's issuer is its client ID.

**Client ID**. The OAuth 2 identifier a platform issues to a tool at registration.

**Deployment**. The scope of contexts in a platform where a tool is available, such as one course or a whole institution. Each deployment has an immutable deployment ID, and many deployments can share one registration.

**Key set**. A JSON Web Key Set at a URL, with the public keys a party signs with, each identified by its `kid`. _Avoid_ JWKS.

**Signing key**. The key pair and key ID a party signs JWTs with, such as the tool's signing key for client assertions and Deep Linking responses, or the platform's signing key for ID tokens. _Avoid_ key pair, tool key.

**Key rotation**. A party adding a new public key to its key set under a new `kid`, keeping the previous key for a while.

### Contexts and users

**Context**. A course, section, group, or project with a common set of users and roles. _Avoid_ course.

**Resource**. An item of content in a context that an LTI link leads to.

**LTI link**. A platform's stored reference to a tool, with the URL and data a launch needs. _Avoid_ placement.

**Resource link**. An LTI link tied to a resource, with a `resource_link_id` unique within the platform.

**User**. A person with a session in a platform, identified to tools by a stable ID.

**Subject identifier**. A platform's unique, never-reassigned ID for a user, sent as the `sub` claim. _Avoid_ user ID.

**Actual user**. The person acting in an impersonation launch, such as an administrator viewing a course as a student, described by the `actual_user` claim.

**Role-scope mentor**. A user, such as a parent or auditor, who can access other users' data, listed by subject identifier in the `role_scope_mentor` claim.

### Roles

**Role**. A URI for a user's level of privilege in a context, an institution, or the system, such as learner or instructor. _Avoid_ role struct.

**Role vocabulary**. A set of role URIs a specification defines. LIS defines context, institution, and system vocabularies, and Core adds LTI system roles. _Avoid_ role scope, role category.

**Role kind**. Context, institution, or system, from the vocabulary a role belongs to. Roles in the LTI system vocabulary are system roles. A deprecated form has the kind of each role it stands for, so `person#Administrator` and `person#None` are both institution and system roles. A role outside the standard vocabularies, such as a platform's own URI, has no kind. _Avoid_ role type.

**Sub-role**. A role that narrows a context role, such as `Instructor#TeachingAssistant`.

**Principal role**. A context role without a sub-role, such as `Instructor`.

### Launches and messages

**Message**. A signed JWT a platform or tool sends to the other through the user's browser.

**Message type**. The kind of a message, given by its `message_type` claim, such as `LtiResourceLinkRequest`. It determines which claims a message must include.

**Claim**. One top-level property of a message's JWT payload, keyed by a URI or a registered OIDC name.

**Extension claim**. A claim a vendor adds to a message, keyed by a URL the vendor controls.

**ID token**. The JWT a platform sends in an authentication response, with the user's identity and the message's claims. _Avoid_ token, on its own.

**Login**. The third-party initiated login request a platform sends to start a launch, before the tool has the user's identity.

**Authentication request**. The redirect from the tool to the platform after login, with a state and a nonce. _Avoid_ authorization redirect, authorization request.

**Authentication response**. The platform's form post to the tool with the ID token and the state.

**Callback**. The tool's handling of the authentication response, which completes a launch.

**State**. An opaque value a tool binds to the browser session in the authentication request and checks in the authentication response, to prevent login CSRF.

**Nonce**. A single-use value a tool sends in the authentication request and the platform returns in the ID token, to prevent replay.

**Launch**. A user following an LTI link into a tool, completed by a message the platform sends through the browser. _Avoid_ launch context, launch claims.

**Resource link launch**. A launch from a resource link, with message type `LtiResourceLinkRequest`.

**Anonymous launch**. A launch without a `sub` claim or other user identity claims.

**Target link URI**. The tool URL a launch ends at.

**Launch presentation**. How the platform hosts the tool's user interface, such as in a frame or a window and at what size, described by the `launch_presentation` claim.

**Custom property**. A string key and value a platform associates with a resource link and sends in the `custom` claim. _Avoid_ custom parameter.

**Platform storage**. Keeping login state in the platform's browser window, for browsers that block the tool's cookie in a frame.

**Variable substitution**. A platform replacing a custom property's `$Variable` value with launch data at launch time.

### Services

**Advantage service**. An HTTP API a platform offers that a tool calls directly with an access token, without the browser, such as AGS or NRPS. Service, on its own, means the same. _Avoid_ extension, platform API.

**Endpoint**. A claim in a message with the URLs, and sometimes scopes, for one service.

**Access token**. A bearer token a platform issues to a tool for calling services, obtained with the OAuth 2 client credentials grant.

**Client assertion**. The JWT a tool signs to authenticate itself when requesting an access token.

**Scope**. A URI for one permission an access token grants, such as reading line items.

**AGS**. Assignment and Grade Services, the specification for line items, scores, and results.

**Line item**. Usually a column in a platform's gradebook, holding the results for one activity in one context.

**Coupled line item**. The line item a platform creates and ties to a resource link.

**Line item container**. A list of line items, such as all of a context's line items for a tool.

**Score**. The latest grade a tool sends for one user on one line item, with the status of the activity and of grading.

**Result**. Usually a cell in a platform's gradebook, holding the current value for one user on one line item.

**NRPS**. Names and Role Provisioning Services, the specification for reading a context's memberships.

**Membership**. A user's relationship to a context, with at least one role.

**Member**. One user and their roles in a membership container.

**Roster**. All of a context's memberships, which NRPS returns in one or more membership containers.

**Membership container**. One NRPS response, with a context and its memberships or one page of them.

### Deep Linking

**Deep Linking**. The specification for a user selecting content in a tool and returning it to the platform as new links.

**Deep Linking request**. The message a platform sends to start Deep Linking, with message type `LtiDeepLinkingRequest`.

**Deep Linking settings**. What a platform accepts in a Deep Linking response, such as content item types and the return URL, described by the `deep_linking_settings` claim.

**Deep Linking response**. The message a tool signs to return content items to a platform, with message type `LtiDeepLinkingResponse`.

**Content item**. One piece of content a tool returns in a Deep Linking response, such as a link or a file.

**Content item type**. The kind of a content item, given by its `type` string. Deep Linking defines `link`, `ltiResourceLink`, `file`, `html`, and `image`.

**Deep Linking line item**. The line item a tool asks a platform to create along with an `ltiResourceLink` content item. It has fewer fields than a line item.

**Presentation target**. Where a platform shows a content item, such as embedded, in an iframe, or in a new window. _Avoid_ presentation document, document target.

## Applications

**Application**. The Elixir application that uses Ltix to act as a tool. _Avoid_ host, host app.

**Source registration**, **source deployment**. The application's own record that a registration or deployment is built from.

**Storage adapter**. The module an application provides to look up registrations and deployments, record used nonces, and sign for the tool. _Avoid_ persistence layer, storage backend.

**Storage adapter contract**. The checks a storage adapter must pass for Ltix to rely on it.

**Key set cache**. The process an application starts that fetches platforms' key sets and keeps them for verifying launches. _Avoid_ key set, JWKS cache.

**Tenant**. An application's unit of isolation, usually one registration or one deployment.

**Auto-created deployment**. A deployment an application creates the first time a verified launch has a deployment ID it hasn't seen.

**Test platform**. A simulated platform for testing an application's launches and service calls.

## Security and errors

**Guarantee**. A property every launch Ltix accepts has, such as a valid signature, a registered issuer, or an unused nonce.

**Platform request**. An HTTP request Ltix sends to a platform, for keys, access tokens, or services.

**Address space**. Whether an address a platform request connects to is public, local, or loopback.

**Ltix error**. An exception Ltix returns for an expected failure.

**Error class**. The kind of an Ltix error. Invalid errors come from bad input or a bad call, security errors from a failed security check, and unknown errors from failures outside the caller's control, such as storage or the network.

## Service clients

**OAuth client**. A tool's authenticated session for calling one platform's services, with an access token and the endpoints it applies to. _Avoid_ authenticated client.

**Stored endpoint**. An endpoint an application saved from a launch, used to call a service later without a launch.

## Plugins

**Plugin**. A module that declares what it provides, what it extends, and which plugins it depends on. _Avoid_ extension, add-on, parser, manifest.

**Default plugin**. A plugin that ships with Ltix and always loads first. These are Core, Deep Linking, AGS, and NRPS. _Avoid_ built-in plugin, bundled plugin.

**Profile**. A plugin that only depends on other plugins, so an application can enable them together. _Avoid_ preset, bundle.

**Dependency**. A plugin another plugin requires. Resolution adds it to the plugin set.

**Enabled plugins**. The plugins an application enables, each as a module or a module with options, in configuration or at a call.

**Plugin set**. The plugins one call into Ltix runs with, including default plugins and dependencies.

**Resolution**. Building a plugin set from the enabled plugins and reporting its conflicts.

**Conflict**. Two plugins making declarations that contradict each other, such as two modules declaring one claim.

**Provider**. A module a plugin provides that defines a struct or type, and the behaviours of the modules that extend it. _Avoid_ target, extension point, hook.

**Step**. A module that receives a login, launch, client assertion, or Deep Linking response and can change it, record an error and continue, or record an error and halt the call.

**Anonymous step**. A step a plugin adds as a function, with its provider's `add_step/2`, such as `Ltix.Login.add_step/2`. No step can order itself against an anonymous step. The word has nothing to do with an anonymous launch.

**Default step**. A step a default plugin provides. Default steps other than phases are internal and can change between releases.

**Phase**. A point in a login or launch that steps order against, such as `Ltix.Login.RegistrationFound`.

## Claims

**Short name**. The atom Ltix uses for a claim, such as `:resource_link`.

**Raw claims**. A message's claims as received, before parsing.

**Declared claim**. A claim that a single module declares and parses. _Avoid_ claim owner, claim parser, and own as a verb for claims.

**Object claim**. A claim whose value is a JSON object with named fields.

**Scalar claim**. A claim whose value is a string, number, or list.

**Lenient claim**. A claim whose malformed value is left out of the parsed claims and kept in the raw claims, without failing the call.

**Check**. A rule about a parsed claim that must pass for a message to be valid, defined by the extender that declares the claim or added by another plugin.

## Message types

**Validator**. The required and optional claims of one message type, combined from every plugin's statements.

**Statement**. One plugin's requirement for one claim in one message type, with a disposition and an optional condition.

**Disposition**. Whether a statement makes a claim required or optional.

**Condition**. Data describing when a statement applies, such as an option being set.

**Contribution**. The statements a plugin adds to a message type another plugin declares.

## Overrides

**Override**. A deviation from Ltix's default behavior by a plugin or an application. Between plugins, an override is one plugin changing or removing another plugin's behavior, such as replacing a check within named message types or making a required claim optional.

## Types and properties

**Type**. A kind of data with standard fields that plugins add properties to, such as a line item, score, content item, or object claim.

**Standard field**. A field a specification defines for a type.

**Property**. One JSON property on a type that a single module declares, parses, and serializes. _Avoid_ claim and own as verbs for properties.

**Extension**. A property's parsed value, stored on the type under its extender. _Avoid_ using "extension" for a plugin, an extender, or an extension claim.

**Unrecognized property**. A property no plugin declares, kept as received and written back unchanged. _Avoid_ unclaimed, unowned.

**Write operation**. Whether a type is being created or updated, which determines the properties it sends.
