# Testing with the IMS Reference Implementation

The [IMS LTI Reference Implementation](https://lti-ri.imsglobal.org)
provides a free test platform you can launch from without needing access
to Canvas, Moodle, or Blackboard. This guide walks through setting it up
with your Ltix-powered tool.

Before starting, complete the [Getting Started](getting-started.md) guide
so you have a running tool with routes, a controller, and a storage adapter.

## Create a platform

1. Go to [Manage Platforms](https://lti-ri.imsglobal.org/platforms) and
   click **Add Platform**
2. Fill in a name, client ID (e.g. `my-tool`), and audience
3. Generate keys at [Generate Keys](https://lti-ri.imsglobal.org/keygen)
   and paste the public and private keys into the platform form
4. Save the platform

## Add a deployment

1. View your platform and click **Platform Keys**
2. Click **Add Platform Key**, give it a name and a deployment ID
   (e.g. `1`)
3. Save and note the **well-known/jwks URL** on this page

## Configure your storage adapter

Copy the values from the RI platform page into your storage adapter.
You need:

| RI Platform field | Storage field |
|---|---|
| Issuer (shown on platform page) | `Registration` `:issuer` |
| Client ID (what you entered) | `Registration` `:client_id` |
| OIDC Auth URL | `Registration` `:auth_endpoint` |
| well-known/jwks URL (from Platform Keys) | `Registration` `:jwks_uri` |
| Deployment ID (from Platform Keys) | `Deployment` `:deployment_id` |

## Add a resource link

1. View your platform and click **Resource Links**
2. Fill in the form with:
   - **Tool link url:** `https://localhost:4000/lti/launch`
   - **Login initiation url:** `https://localhost:4000/lti/login`
3. Save

## Add a course

1. View your platform and click **Courses**
2. Fill in a course name and save

## Launch

1. View your platform and click **Resource Links**
2. Click **Select User for Launch**, then **Launch with New User**
3. Scroll down and click **Perform Launch**

If everything is configured correctly, you'll see your launch page
with the parsed launch data: user info, roles, context, and resource
link.

## Troubleshooting

If the launch fails silently, check these common issues:

- **Self-signed certificate not accepted.** Visit `https://localhost:4000`
  in your browser and accept the certificate warning before attempting a
  launch. Otherwise the platform's redirect will fail without an error.
- **Session cookie not sent.** Make sure your endpoint uses
  `same_site: "None"` and `secure: true`. See
  [Getting Started](getting-started.md#configure-phoenix-for-cross-origin-launches)
  for details.
- **Mismatched issuer or client_id.** Double-check that the values in
  your storage adapter match the RI platform page exactly.
