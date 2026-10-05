defmodule Ltix.JWT.KeySetTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.JWT.KeySet
  alias Ltix.JWT.KeySet.ETSCache

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
    test "re-fetches an unknown kid when the cached keys are at least 30 seconds old", ctx do
      rotated_jwk = Ltix.JWK.generate()
      fetch_count = count_fetches(Ltix.JWK.to_jwks([ctx.platform_jwk, rotated_jwk]))
      cache_keys(ctx, fetched_seconds_ago: 30)

      kid = rotated_jwk.kid

      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
               KeySet.get_key(ctx.registration, kid, req_options: req_options())

      assert :counters.get(fetch_count, 1) == 1

      assert {:ok, %{keys: %{^kid => _jwk}}} = ETSCache.get(ctx.registration.jwks_uri)
    end

    # [Sec §6.4](https://www.imsglobal.org/spec/security/v1p0/#issuer-public-key-rotation)
    test "does not re-fetch an unknown kid within 30 seconds of the last fetch", ctx do
      fetch_count = count_fetches(ctx.jwks)
      opts = [req_options: req_options()]

      assert {:ok, _jwk} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)

      for kid <- ["unknown-kid-1", "unknown-kid-2"] do
        assert {:error, %Ltix.Errors.Security.KidNotFound{kid: ^kid}} =
                 KeySet.get_key(ctx.registration, kid, opts)
      end

      assert :counters.get(fetch_count, 1) == 1
    end

    test "does not re-fetch a kid missing from a key set it just fetched", ctx do
      fetch_count = count_fetches(ctx.jwks)

      assert {:error, %Ltix.Errors.Security.KidNotFound{}} =
               KeySet.get_key(ctx.registration, "unknown-kid", req_options: req_options())

      assert :counters.get(fetch_count, 1) == 1
    end

    test "keeps the cached keys when re-fetching for an unknown kid fails", ctx do
      Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(503, "unavailable")
      end)

      cache_keys(ctx, fetched_seconds_ago: 60)

      assert {:error, %TransportError{status: 503}} =
               KeySet.get_key(ctx.registration, "unknown-kid",
                 req_options: req_options() ++ [retry: false]
               )

      kid = ctx.platform_jwk.kid

      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
               KeySet.get_key(ctx.registration, kid, req_options: req_options())
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

    test "skips malformed keys in the key set", ctx do
      [platform_key] = ctx.jwks["keys"]
      keys = [123, "key", %{"kid" => "no-type"}, %{"kty" => "RSA", "kid" => "bad", "n" => 1}]
      stub_jwks(%{"keys" => keys ++ [platform_key]})

      kid = ctx.platform_jwk.kid
      opts = [req_options: req_options()]

      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
               KeySet.get_key(ctx.registration, kid, opts)

      for kid <- ["no-type", "bad"] do
        assert {:error, %Ltix.Errors.Security.KidNotFound{kid: ^kid}} =
                 KeySet.get_key(ctx.registration, kid, opts)
      end
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

  defp count_fetches(jwks) do
    fetch_count = :counters.new(1, [:atomics])

    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      :counters.add(fetch_count, 1, 1)

      conn
      |> Plug.Conn.put_resp_header("cache-control", "max-age=300")
      |> Req.Test.json(jwks)
    end)

    fetch_count
  end

  # Caches the test's platform key as fetched the given number of seconds ago.
  defp cache_keys(ctx, fetched_seconds_ago: seconds) do
    entry = %{
      keys: %{ctx.platform_jwk.kid => JOSE.JWK.from_map(hd(ctx.jwks["keys"]))},
      fetched_at: DateTime.add(DateTime.utc_now(), -seconds)
    }

    ETSCache.put(ctx.registration.jwks_uri, entry, 300)
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
