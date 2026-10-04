defmodule Ltix.JWT.KeySetTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.JWT.KeySet

  @tool_jwk Ltix.JWK.generate()

  setup do
    platform_jwk = Ltix.JWK.generate()
    jwks = Ltix.JWK.to_jwks(platform_jwk)

    # Unique JWKS URI per test to avoid cache interference in async tests
    unique_id = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

    {:ok, registration} =
      Ltix.Registration.new(%{
        issuer: "https://platform.example.com",
        client_id: "tool-client-id",
        auth_endpoint: "https://platform.example.com/auth",
        jwks_uri: "https://platform.example.com/.well-known/jwks-#{unique_id}.json",
        tool_jwk: @tool_jwk
      })

    %{registration: registration, platform_jwk: platform_jwk, jwks: jwks}
  end

  describe "get_key/3" do
    test "raises on unknown and invalid options", ctx do
      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :request_options is unknown", fn ->
        KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, request_options: [])
      end

      assert_raise Ltix.Errors.Invalid.InvalidOption, ~r/Option :jwks_cache is invalid/, fn ->
        KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, jwks_cache: "cache")
      end
    end

    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "fetches and selects key by kid", ctx do
      stub_jwks(ctx.jwks)

      kid = ctx.platform_jwk.kid

      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
               KeySet.get_key(ctx.registration, kid, req_options: req_options())
    end

    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "selects correct key from multi-key JWKS", ctx do
      second_jwk = Ltix.JWK.generate()
      jwks = Ltix.JWK.to_jwks([ctx.platform_jwk, second_jwk])
      stub_jwks(jwks)

      kid = second_jwk.kid

      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
               KeySet.get_key(ctx.registration, kid, req_options: req_options())
    end

    # [Cert §6.1.1] "Incorrect KID in JWT header"
    test "returns KidNotFound when kid not in JWKS", ctx do
      stub_jwks(ctx.jwks)

      assert {:error, %Ltix.Errors.Security.KidNotFound{kid: "wrong-kid"}} =
               KeySet.get_key(ctx.registration, "wrong-kid", req_options: req_options())
    end

    # [Sec §6.4](https://www.imsglobal.org/spec/security/v1p0/#issuer-public-key-rotation)
    test "re-fetches on unknown kid for key rotation", ctx do
      second_jwk = Ltix.JWK.generate()

      # First stub: only original key
      stub_jwks(ctx.jwks)

      # Fetch original key to populate cache
      assert {:ok, _jwk} =
               KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, req_options: req_options())

      # Now stub with both keys (simulates key rotation)
      jwks_rotated = Ltix.JWK.to_jwks([ctx.platform_jwk, second_jwk])
      stub_jwks(jwks_rotated)

      # Should re-fetch and find the new key
      kid = second_jwk.kid

      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
               KeySet.get_key(ctx.registration, kid, req_options: req_options())
    end

    # [Sec §6.4](https://www.imsglobal.org/spec/security/v1p0/#issuer-public-key-rotation)
    test "re-fetches at most once per kid miss", ctx do
      fetch_count = :counters.new(1, [:atomics])

      Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
        :counters.add(fetch_count, 1, 1)

        conn
        |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
        |> Req.Test.json(ctx.jwks)
      end)

      # This should fetch once, miss, re-fetch once, still miss → KidNotFound
      assert {:error, %Ltix.Errors.Security.KidNotFound{}} =
               KeySet.get_key(ctx.registration, "nonexistent-kid", req_options: req_options())

      # Should have fetched exactly 2 times (initial + one re-fetch)
      assert :counters.get(fetch_count, 1) == 2
    end

    test "returns error for non-200 HTTP response", ctx do
      Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(404, "Not Found")
      end)

      jwks_uri = ctx.registration.jwks_uri

      assert {:error, %TransportError{status: 404, url: ^jwks_uri, spec_ref: "Sec §6.3"}} =
               KeySet.get_key(ctx.registration, ctx.platform_jwk.kid,
                 req_options: req_options() ++ [retry: false]
               )
    end

    test "returns AccessDenied when the key set endpoint answers HTTP 401", ctx do
      Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(401, "denied")
      end)

      jwks_uri = ctx.registration.jwks_uri

      assert {:error,
              %Ltix.Errors.Security.AccessDenied{
                status: 401,
                url: ^jwks_uri,
                spec_ref: "Sec §6.3"
              }} =
               KeySet.get_key(ctx.registration, ctx.platform_jwk.kid,
                 req_options: req_options() ++ [retry: false]
               )
    end

    test "handles JWKS with no keys array gracefully", ctx do
      Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
        |> Req.Test.json(%{"not_keys" => []})
      end)

      assert {:error, %Ltix.Errors.Security.KidNotFound{}} =
               KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, req_options: req_options())
    end

    test "returns TransportError on network failure", ctx do
      Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      jwks_uri = ctx.registration.jwks_uri

      assert {:error, %TransportError{status: nil, url: ^jwks_uri}} =
               KeySet.get_key(ctx.registration, ctx.platform_jwk.kid,
                 req_options: req_options() ++ [retry: false]
               )
    end

    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "caches JWKS and serves from cache on subsequent calls", ctx do
      fetch_count = :counters.new(1, [:atomics])

      Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
        :counters.add(fetch_count, 1, 1)

        conn
        |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
        |> Req.Test.json(ctx.jwks)
      end)

      opts = [req_options: req_options()]

      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)
      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)
      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)

      # Only one HTTP fetch
      assert :counters.get(fetch_count, 1) == 1
    end

    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "does not cache when max-age=0", ctx do
      fetch_count = :counters.new(1, [:atomics])

      Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
        :counters.add(fetch_count, 1, 1)

        conn
        |> Plug.Conn.put_resp_header("cache-control", "max-age=0")
        |> Req.Test.json(ctx.jwks)
      end)

      opts = [req_options: req_options()]

      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)
      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)

      # max-age=0 means no caching, so two fetches
      assert :counters.get(fetch_count, 1) == 2
    end

    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "uses default max-age when no cache-control header", ctx do
      fetch_count = :counters.new(1, [:atomics])

      Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
        :counters.add(fetch_count, 1, 1)

        conn
        |> Plug.Conn.delete_resp_header("cache-control")
        |> Req.Test.json(ctx.jwks)
      end)

      opts = [req_options: req_options()]

      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)
      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)

      # Default max-age applies, so only one fetch
      assert :counters.get(fetch_count, 1) == 1
    end
  end

  defp stub_jwks(jwks) do
    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)
  end

  defp req_options do
    [plug: {Req.Test, Ltix.JWT.KeySet}]
  end
end
