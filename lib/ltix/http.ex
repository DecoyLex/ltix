defmodule Ltix.HTTP do
  @moduledoc false

  alias Ltix.Errors.Unknown.TransportError

  @doc """
  Merge application-level `req_options` with caller-provided options and
  rewrite any `Req.Test` plug to use the given stub name.

  Used by every module that makes an outbound HTTP call so that:

  1. `config :ltix, req_options: [...]` is always respected.
  2. A single `plug: {Req.Test, :ltix}` config entry routes each
     callsite to its own well-known stub name.
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
  """
  @spec request(keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def request(opts) do
    case validate_url(Keyword.get(opts, :url)) do
      {:ok, uri} -> Req.request(Keyword.put(opts, :url, uri))
      {:error, error} -> {:error, error}
    end
  end

  @doc false
  @spec validate_url(term()) :: {:ok, URI.t()} | {:error, TransportError.t()}
  # [Sec §3](https://www.imsglobal.org/spec/security/v1p0/#transport-security)
  # [RFC 6750 §5.3](https://www.rfc-editor.org/rfc/rfc6750#section-5.3)
  def validate_url(url) when is_binary(url) do
    with {:ok, %URI{scheme: scheme, host: host, userinfo: nil} = uri}
         when is_binary(scheme) and is_binary(host) and host != "" <- URI.new(url),
         true <- String.downcase(scheme, :ascii) == "https",
         port = uri.port || 443,
         true <- port in 1..65_535 do
      {:ok, %{uri | scheme: "https", host: String.downcase(host, :ascii), port: port}}
    else
      _ -> invalid_url()
    end
  end

  def validate_url(_url), do: invalid_url()

  defp invalid_url do
    {:error,
     TransportError.exception(
       body:
         "Endpoint must be an absolute HTTPS URL without a userinfo component (RFC 3986 §3.2.1)",
       spec_ref: "Sec §3, RFC 6750 §5.3"
     )}
  end

  defp rewrite_test_plug(opts, stub_name) do
    case Keyword.get(opts, :plug) do
      {Req.Test, _} -> Keyword.put(opts, :plug, {Req.Test, stub_name})
      _ -> opts
    end
  end
end
