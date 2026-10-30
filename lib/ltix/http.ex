defmodule Ltix.HTTP do
  @moduledoc false

  alias Ltix.AppConfig
  alias Ltix.Errors
  alias Ltix.Errors.Invalid.MalformedResponse
  alias Ltix.Errors.Security.AccessDenied
  alias Ltix.Errors.Security.LocalNetworkAccessDenied
  alias Ltix.Errors.Unknown.RedirectNotAllowed
  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.HTTP.AddressSpace

  @doc """
  The `:local_network_access` option of every function that sends platform
  requests.
  """
  @spec local_network_access_option() :: Zoi.schema()
  def local_network_access_option do
    Zoi.nullish(
      Zoi.enum([:none, :local, :loopback],
        description: """
        The non-public addresses Ltix may connect to when it calls a platform.
        Defaults to `:none`. `:local` allows private network addresses, and
        `:loopback` allows those and this machine. The `:finch`, `:adapter`,
        `:unix_socket`, and proxy options in `:req_options` require `:loopback`,
        as do its `:tcp_module` and `:cb_info` transport options.
        """
      )
    )
  end

  @doc """
  Merge application-level `req_options` with caller-provided options and
  rewrite any `Req.Test` plug to use the given stub name.

  Used by every module that makes an outbound HTTP call. This has two effects.

  1. `config :ltix, req_options: [...]` always applies.
  2. A single `plug: {Req.Test, :ltix}` config entry makes each
     call site use its own well-known stub name.
  """
  @spec req_options(keyword(), module()) :: keyword()
  def req_options(caller_opts, stub_name) do
    default = Application.get_env(:ltix, :req_options, [])

    default
    |> Keyword.merge(caller_opts)
    |> rewrite_test_plug(stub_name)
  end

  @doc """
  Send a request only to an absolute HTTPS URL without a userinfo component (RFC 3986 §3.2.1).

  HTTP is accepted for loopback and local hosts. A request that connects to a
  local or loopback address returns `Ltix.Errors.Security.LocalNetworkAccessDenied`
  unless the `:local_network_access` option or configuration allows it.

  A request that cannot connect to the platform returns `Ltix.Errors.Unknown.TransportError`.
  A JSON body is decoded unless `decode_body: false` is given. Invalid JSON in a
  successful response returns `Ltix.Errors.Invalid.MalformedResponse`, labeled
  with the `:service` option, and in an error response is left as the raw body.
  """
  @spec request(keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def request(opts) do
    {labels, opts} = Keyword.split(opts, [:service])
    {decode?, opts} = Keyword.pop(opts, :decode_body, true)
    {access, opts} = Keyword.pop(opts, :local_network_access)
    url = Keyword.get(opts, :url)

    with {:ok, uri} <- validate_url(url),
         :ok <- validate_certificate_verification(opts),
         {:ok, opts} <-
           restrict_addresses(opts, uri, url, access || AppConfig.local_network_access()) do
      opts
      |> Keyword.merge(
        url: uri,
        redirect: true,
        redirect_log_level: false,
        max_redirects: max_redirects(opts),
        decode_body: false
      )
      |> Keyword.delete(:follow_redirects)
      |> Req.new()
      |> Req.Request.prepend_response_steps(ltix_redirect: &guard_redirect(&1, uri))
      |> Req.request()
      |> to_ltix_error(url)
      |> decode_json(decode?, url, labels)
    end
  end

  @doc """
  Send a request with `request/1` and return `status_error/2` for a response
  without a successful status.
  """
  @spec request_success(keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def request_success(opts) do
    case request(opts) do
      {:ok, %Req.Response{status: status} = response} when status not in 200..299 ->
        {:error, status_error(response, Keyword.get(opts, :url))}

      result ->
        result
    end
  end

  defp decode_json({:ok, %Req.Response{status: status, body: body} = response}, true, url, labels)
       when is_binary(body) and body != "" do
    if json_content_type?(response) do
      case AppConfig.json_library!().decode(body) do
        {:ok, decoded} ->
          {:ok, %{response | body: decoded}}

        {:error, _reason} when status in 200..299 ->
          {:error,
           MalformedResponse.exception(
             [reason: "response from #{url} is not valid JSON"] ++ labels
           )}

        {:error, _reason} ->
          {:ok, response}
      end
    else
      {:ok, response}
    end
  end

  defp decode_json(result, _decode?, _url, _labels), do: result

  defp json_content_type?(response) do
    response
    |> Req.Response.get_header("content-type")
    |> Enum.any?(fn content_type ->
      [media_type | _parameters] = String.split(content_type, ";")
      media_type = String.downcase(String.trim(media_type), :ascii)
      media_type == "application/json" || String.ends_with?(media_type, "+json")
    end)
  end

  # [LNA §2.2](https://wicg.github.io/local-network-access/#local-network-request)
  defp to_ltix_error({:error, %Req.TransportError{reason: {:ltix_address_space, space}}}, url) do
    {:error, LocalNetworkAccessDenied.exception(url: url, address_space: space)}
  end

  defp to_ltix_error({:error, error}, url) do
    if Errors.ltix_error?(error) do
      {:error, error}
    else
      {:error, TransportError.exception(body: Exception.message(error), url: url)}
    end
  end

  defp to_ltix_error(result, _url), do: result

  @doc false
  @spec status_error(Req.Response.t(), String.t()) :: Exception.t()
  # [RFC 6750 §3.1](https://www.rfc-editor.org/rfc/rfc6750#section-3.1)
  def status_error(%Req.Response{status: status, body: body}, url) when status in [401, 403] do
    AccessDenied.exception(status: status, body: body, url: url)
  end

  def status_error(%Req.Response{status: status, body: body, headers: headers}, url) do
    TransportError.exception(status: status, body: body, headers: headers, url: url)
  end

  @doc false
  @spec validate_url(term()) :: {:ok, URI.t()} | {:error, TransportError.t()}
  # [Sec §3](https://www.imsglobal.org/spec/security/v1p0/#transport-security)
  # [RFC 6750 §5.3](https://www.rfc-editor.org/rfc/rfc6750#section-5.3)
  # Browsers treat loopback hosts as secure and relax mixed content for local
  # addresses. The address a request connects to is checked separately.
  # [Secure Contexts §3.1](https://www.w3.org/TR/secure-contexts/#is-origin-trustworthy)
  # [LNA §2.5](https://wicg.github.io/local-network-access/#mixed-content)
  def validate_url(url) when is_binary(url) do
    with {:ok, %URI{scheme: scheme, host: host, userinfo: nil} = uri}
         when is_binary(scheme) and is_binary(host) and host != "" <- URI.new(url),
         scheme = String.downcase(scheme, :ascii),
         host = String.downcase(host, :ascii),
         true <- scheme == "https" || (scheme == "http" && host_address_space(host) != :public),
         port = uri.port || URI.default_port(scheme),
         true <- port in 1..65_535 do
      {:ok, %{uri | scheme: scheme, host: host, port: port}}
    else
      _ -> invalid_url()
    end
  end

  def validate_url(_url), do: invalid_url()

  # A Zoi refinement for a field that `validate_url/1` accepts.
  @doc false
  @spec https_url(term(), keyword()) :: :ok | {:error, String.t()}
  def https_url(url, _opts) do
    case validate_url(url) do
      {:ok, _uri} -> :ok
      {:error, _error} -> {:error, "must be an absolute HTTPS URL"}
    end
  end

  # The address space a host is known to be in before it is resolved.
  # `localhost` and names under it are loopback.
  # [RFC 6761 §6.3](https://www.rfc-editor.org/rfc/rfc6761#section-6.3)
  defp host_address_space(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} ->
        AddressSpace.classify(address)

      {:error, :einval} ->
        if host == "localhost" || String.ends_with?(host, ".localhost"),
          do: :loopback,
          else: :public
    end
  end

  # Refuses hosts known to be outside the allowed address spaces. An HTTPS
  # connection then refuses each address the host name resolves to that
  # `access` doesn't allow. An HTTP request needs no transport check. Its host
  # is an IP address, which is the address it connects to, or `localhost` or a
  # name under it, which needs loopback access, and loopback access allows
  # every address.
  # [LNA §2.2](https://wicg.github.io/local-network-access/#local-network-request)
  defp restrict_addresses(opts, uri, url, access) do
    space = host_address_space(uri.host)
    option = unchecked_connection_option(opts)

    cond do
      !AddressSpace.allowed?(space, access) ->
        {:error, LocalNetworkAccessDenied.exception(url: url, address_space: space)}

      option == nil && uri.scheme == "https" ->
        {:ok, put_tls_transport_options(opts, access)}

      option == nil || access == :loopback ->
        {:ok, opts}

      true ->
        {:error,
         TransportError.exception(
           body:
             "The #{inspect(option)} request option requires local_network_access: :loopback, " <>
               "because Ltix can't check the addresses it connects to",
           url: url
         )}
    end
  end

  # The option, if any, that makes the request connect somewhere other than
  # the address the URL's host resolves to, where the address check can't run.
  defp unchecked_connection_option(opts) do
    cond do
      option = Enum.find([:finch, :adapter, :unix_socket], &(Keyword.get(opts, &1) != nil)) ->
        option

      get_in(opts, [:connect_options, :proxy]) != nil ->
        :proxy

      option =
          Enum.find(
            [:tcp_module, :cb_info],
            &(get_in(opts, [:connect_options, :transport_opts, &1]) != nil)
          ) ->
        option

      true ->
        nil
    end
  end

  defp put_tls_transport_options(opts, access) do
    transport_options = AddressSpace.tls_transport_options(access)

    Keyword.update(
      opts,
      :connect_options,
      [transport_opts: transport_options],
      &Keyword.update(&1, :transport_opts, transport_options, fn caller_options ->
        Keyword.merge(caller_options, transport_options)
      end)
    )
  end

  # [RFC 6750 §5.3](https://www.rfc-editor.org/rfc/rfc6750#section-5.3)
  defp validate_certificate_verification(opts) do
    finch_options =
      case Keyword.get(opts, :finch) do
        opts when is_list(opts) -> opts
        _ -> []
      end

    if get_in(opts, [:connect_options, :transport_opts, :verify]) == :verify_none ||
         get_in(finch_options, [:conn_opts, :transport_opts, :verify]) == :verify_none do
      {:error,
       TransportError.exception(body: "Platform requests require TLS certificate verification")}
    else
      :ok
    end
  end

  # [RFC 6750 §5.3](https://www.rfc-editor.org/rfc/rfc6750#section-5.3)
  defp guard_redirect(
         {request, %Req.Response{status: status, body: %Req.Response.Async{}} = response},
         origin
       )
       when status in 300..399 do
    Req.cancel_async_response(response)
    guard_redirect({request, %{response | body: ""}}, origin)
  end

  defp guard_redirect({request, %Req.Response{status: status} = response}, origin)
       when status in 300..399 do
    with true <- status in [301, 302, 303, 307, 308],
         [location | _] when location != "" <- Req.Response.get_header(response, "location"),
         {:ok, target} <- URI.new(location),
         {:ok, target} <- validate_url(URI.to_string(URI.merge(request.url, target))),
         true <-
           {target.scheme, target.host, target.port} ==
             {origin.scheme, origin.host, origin.port} do
      # Req handles redirect processing and the redirect limit.
      # Normalize the target so equivalent origins retain credentials.
      {normalize_redirect_request(request, status),
       Req.Response.put_header(response, "location", URI.to_string(target))}
    else
      _ -> reject_redirect(request, response)
    end
  end

  defp guard_redirect({request, response}, _origin) do
    {request, Req.Response.put_private(response, :ltix_response_url, URI.to_string(request.url))}
  end

  # Req converts only POST for 303. Other mutations require retrieval too.
  # [RFC 9110 §15.4.4](https://www.rfc-editor.org/rfc/rfc9110#section-15.4.4)
  defp normalize_redirect_request(request, 303) when request.method not in [:get, :head, :post] do
    request
    |> Map.merge(%{method: :get, body: nil})
    |> Req.Request.drop_options([:json, :form, :form_multipart])
    |> Req.Request.delete_header("content-type")
    |> Req.Request.delete_header("content-length")
  end

  defp normalize_redirect_request(request, _status), do: request

  defp reject_redirect(request, response) do
    error =
      RedirectNotAllowed.exception(
        status: response.status,
        url: URI.to_string(%{request.url | userinfo: nil, query: nil, fragment: nil}),
        location: redirect_location(response)
      )

    Req.Request.halt(request, error)
  end

  defp max_redirects(opts) do
    case Keyword.get(opts, :max_redirects, 10) do
      count when is_integer(count) and count >= 0 -> count
      _ -> 10
    end
  end

  defp redirect_location(response) do
    with [location | _] <- Req.Response.get_header(response, "location"),
         {:ok, uri} <- URI.new(location) do
      location = URI.to_string(%{uri | userinfo: nil, query: nil, fragment: nil})
      if location == "", do: nil, else: location
    else
      _ -> nil
    end
  end

  defp invalid_url do
    {:error,
     TransportError.exception(
       body:
         "Endpoint must be an absolute HTTPS URL, or an HTTP URL for a loopback or local host, " <>
           "without a userinfo component (RFC 3986 §3.2.1)"
     )}
  end

  defp rewrite_test_plug(opts, stub_name) do
    case Keyword.get(opts, :plug) do
      {Req.Test, _} -> Keyword.put(opts, :plug, {Req.Test, stub_name})
      _ -> opts
    end
  end
end
