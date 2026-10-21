# Keeping Login State in Platform Storage

A launch is a login request followed by a cross-site POST. Your tool checks that one browser sent both by comparing the state in the session cookie with the state in the POST. Some browsers block cookies inside an iframe, and then the launch fails with a state mismatch.

Platforms that support [LTI Platform Storage](https://www.imsglobal.org/spec/lti-cs-oidc/v0p1) store the state for you. Your page sends the state to the platform's window with `postMessage`, and requests it again when the launch arrives. Canvas supports it.

This cookbook adds platform storage to the controller from [Getting Started](../getting-started.md). The controller uses the session cookie when the browser sends it, and platform storage otherwise.

## How it works

1. The platform adds `lti_storage_target` to the login request. It is the name of the frame that stores data.
2. Your login endpoint renders a page that sends `lti.put_data` to that frame, then redirects to the platform.
3. The platform POSTs the launch. Without a session, your launch endpoint renders a page that sends `lti.get_data`.
4. That page posts the state from the response, with the ID token, to a second endpoint on your tool.
5. The second endpoint passes the stored state to `Ltix.handle_callback/3`.

Each message is sent only to the origin of the platform's authorization endpoint. A page from any other site that frames your tool can't read the state or send a response the page accepts.

## Routes

The verify route accepts requests only from your own pages. Any other site could otherwise post an ID token and a matching state directly to the route, and skip the check your launch page does.

```elixir
# lib/my_app_web/router.ex
pipeline :same_origin do
  plug :require_same_origin
end

scope "/lti", MyAppWeb do
  pipe_through :lti_launch

  get "/login", LtiController, :login
  post "/login", LtiController, :login
  post "/launch", LtiController, :launch
end

scope "/lti", MyAppWeb do
  pipe_through [:lti_launch, :same_origin]

  post "/launch/verify", LtiController, :verify
end

# Browsers set this header themselves, and a page can't change it.
defp require_same_origin(conn, _opts) do
  if get_req_header(conn, "sec-fetch-site") == ["same-origin"] do
    conn
  else
    conn |> send_resp(:forbidden, "") |> halt()
  end
end
```

## Controller

```elixir
# lib/my_app_web/controllers/lti_controller.ex
def login(conn, params) do
  launch_url = url(conn, ~p"/lti/launch")

  case Ltix.handle_login(params, launch_url) do
    {:ok, %{redirect_uri: redirect_uri, state: state}} ->
      conn
      |> put_session(:lti_state, state)
      |> redirect_to_platform(params, redirect_uri, state)

    {:error, error} ->
      launch_failed(conn, error)
  end
end

defp redirect_to_platform(conn, %{"lti_storage_target" => target}, redirect_uri, state)
     when is_binary(target) do
  render(conn, :store_state,
    target: target,
    origin: Lti.origin(redirect_uri),
    state: state,
    redirect_uri: redirect_uri
  )
end

defp redirect_to_platform(conn, _params, redirect_uri, _state) do
  redirect(conn, external: redirect_uri)
end

def launch(conn, params) do
  case get_session(conn, :lti_state) do
    nil -> fetch_state(conn, params)
    state -> complete_launch(conn, params, state)
  end
end

def verify(conn, params) do
  complete_launch(conn, params, params["stored_state"])
end

defp fetch_state(
       conn,
       %{"lti_storage_target" => target, "state" => state, "id_token" => id_token} = params
     )
     when is_binary(target) and is_binary(state) and is_binary(id_token) do
  case Lti.platform_origin(id_token) do
    {:ok, origin} ->
      render(conn, :fetch_state,
        target: target,
        origin: origin,
        state: state,
        id_token: id_token
      )

    :error ->
      complete_launch(conn, params, nil)
  end
end

defp fetch_state(conn, params), do: complete_launch(conn, params, nil)

defp complete_launch(conn, params, state) do
  case Ltix.handle_callback(params, state) do
    {:ok, launch} ->
      user = Lti.create_user!(launch)
      course = Lti.create_course!(launch)

      conn
      |> delete_session(:lti_state)
      |> put_session(:user_id, user.id)
      |> put_session(:course_id, course.id)
      |> render(:launch, launch: launch, user: user, course: course)

    {:error, error} ->
      launch_failed(conn, error)
  end
end
```

A launch with no session and no platform storage calls `complete_launch/3` with `nil`, which returns the state mismatch error.

## Finding the platform's origin

The launch page needs the platform's origin before the ID token is verified. Read the issuer and client ID from the unverified token, and use them only to look up a registration you already trust. `Ltix.handle_callback/3` verifies the token afterward.

```elixir
# lib/my_app/lti.ex
def platform_origin(id_token) do
  with [_header, payload, _signature] <- String.split(id_token, "."),
       {:ok, json} <- Base.url_decode64(payload, padding: false),
       {:ok, %{"iss" => issuer, "aud" => audience}} when is_binary(issuer) <- Jason.decode(json),
       [client_id | _] when is_binary(client_id) <- List.wrap(audience),
       {:ok, registration} <- get_registration(issuer, client_id) do
    {:ok, origin(registration.auth_endpoint)}
  else
    _ -> :error
  end
end

def origin(url) do
  %URI{scheme: scheme, host: host, port: port} = URI.parse(url)
  URI.to_string(%URI{scheme: scheme, host: host, port: port})
end
```

## Pages

Both pages use one component for the messaging. It sends a message to the platform's frame and passes the response to a callback. It checks the response's origin, subject, and message ID. After five seconds with no response, it passes `null`.

```elixir
# lib/my_app_web/controllers/lti_html.ex
defmodule MyAppWeb.LtiHTML do
  use MyAppWeb, :html

  embed_templates "lti_html/*"

  attr :target, :string, required: true
  attr :origin, :string, required: true

  def platform_storage(assigns) do
    ~H"""
    <script id="lti-platform-storage" data-target={@target} data-origin={@origin}>
      window.ltiPlatformStorage = (message, done) => {
        const { target, origin } = document.getElementById("lti-platform-storage").dataset
        const platform = window.parent === window ? window.opener : window.parent
        const frame = target === "_parent" ? platform : platform && platform.frames[target]
        const messageId = crypto.randomUUID()
        let finished = false

        const finish = (data) => {
          if (finished) return
          finished = true
          window.removeEventListener("message", receive)
          done(data)
        }

        const receive = (event) => {
          const data = event.data
          if (event.origin !== origin || typeof data !== "object" || data === null) return
          if (data.subject !== message.subject + ".response") return
          if (data.message_id !== messageId) return
          finish(data.error ? null : data)
        }

        window.addEventListener("message", receive)
        setTimeout(() => finish(null), 5000)

        if (frame) {
          frame.postMessage({ ...message, message_id: messageId }, origin)
        } else {
          finish(null)
        }
      }
    </script>
    """
  end
end
```

The login page stores the state under a key that includes the state, so two launches in one browser don't overwrite each other. It redirects even when the platform doesn't respond, because the browser may still send the session cookie.

```heex
<%!-- lib/my_app_web/controllers/lti_html/store_state.html.heex --%>
<p>Launching…</p>

<.platform_storage target={@target} origin={@origin} />

<script id="lti-store-state" data-state={@state} data-redirect-uri={@redirect_uri}>
  const { state, redirectUri } = document.getElementById("lti-store-state").dataset

  window.ltiPlatformStorage(
    { subject: "lti.put_data", key: "lti_state_" + state, value: state },
    () => window.location.replace(redirectUri)
  )
</script>
```

The launch page requests the state and posts it to the verify route.

```heex
<%!-- lib/my_app_web/controllers/lti_html/fetch_state.html.heex --%>
<p id="lti-status">Launching…</p>

<form id="lti-verify" method="post" action={~p"/lti/launch/verify"}>
  <input type="hidden" name="state" value={@state} />
  <input type="hidden" name="id_token" value={@id_token} />
  <input type="hidden" name="stored_state" />
</form>

<.platform_storage target={@target} origin={@origin} />

<script>
  const form = document.getElementById("lti-verify")

  window.ltiPlatformStorage(
    { subject: "lti.get_data", key: "lti_state_" + form.elements.state.value },
    (data) => {
      if (data && typeof data.value === "string") {
        form.elements.stored_state.value = data.value
        form.submit()
      } else {
        document.getElementById("lti-status").textContent =
          "The launch could not be completed. Close this page and open the tool again."
      }
    }
  )
</script>
```

If your tool sends a `script-src` content security policy, add a nonce to these scripts or serve them from a file.

## After the launch

Platform storage holds only the login state. Your tool still needs a session cookie after the launch. The verify request comes from your own page inside the platform's iframe, so a `Partitioned` session cookie set on its response is kept by browsers that support partitioned cookies. See [Getting Started](../getting-started.md#iframe-strategy).

## Limits

- The platform has to send `lti_storage_target` on the launch as well as the login. When a platform sends it only on the login, the launch uses the session cookie.
- The platform's page must stay loaded between the login and the launch. Platforms that support the specification do this.
- A registered platform can read the state it stores and return any value for it. Ltix trusts registered platforms. See the [Threat Model](../threat-model.md).

## Next steps

- [Hardening Your Tool](../hardening.md) for the session cookie attributes and the routes after the launch
- [Getting Started](../getting-started.md) for the controller this cookbook changes
- [LTI Client Side postMessages](https://www.imsglobal.org/spec/lti-cs-pm/v0p1) and [LTI postMessage Storage](https://www.imsglobal.org/spec/lti-pm-s/v0p1) for the message formats
