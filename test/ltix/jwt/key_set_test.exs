defmodule Ltix.JWT.KeySetTest do
  use ExUnit.Case, async: true

  alias Ltix.JWT.KeySet
  alias Ltix.Test.JWTHelper

  @tool_jwk elem(Ltix.JWK.generate_key_pair(), 0)

  setup do
    {_private, public, kid} = JWTHelper.generate_rsa_key_pair()
    jwks = JWTHelper.build_jwks([public])

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

    %{registration: registration, public: public, kid: kid, jwks: jwks}
  end

  describe "get_key/3" do
    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "fetches and selects key by kid", ctx do
      stub_jwks(ctx.jwks)

      assert {:ok, _jwk} = KeySet.get_key(ctx.registration, ctx.kid, req_options: req_options())
    end

    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "selects correct key from multi-key JWKS", ctx do
      {_private2, public2, kid2} = JWTHelper.generate_rsa_key_pair()
      jwks = JWTHelper.build_jwks([ctx.public, public2])
      stub_jwks(jwks)

      assert {:ok, _jwk} = KeySet.get_key(ctx.registration, kid2, req_options: req_options())
    end

    # [Cert §6.1.1] "Incorrect KID in JWT header"
    test "returns KidNotFound when kid not in JWKS", ctx do
      stub_jwks(ctx.jwks)

      assert {:error, %Ltix.Errors.Security.KidNotFound{kid: "wrong-kid"}} =
               KeySet.get_key(ctx.registration, "wrong-kid", req_options: req_options())
    end

    # [Sec §6.4](https://www.imsglobal.org/spec/security/v1p0/#issuer-public-key-rotation)
    test "re-fetches on unknown kid for key rotation", ctx do
      {_private2, public2, kid2} = JWTHelper.generate_rsa_key_pair()

      # First stub: only original key
      stub_jwks(ctx.jwks)

      # Fetch original key to populate cache
      assert {:ok, _jwk} = KeySet.get_key(ctx.registration, ctx.kid, req_options: req_options())

      # Now stub with both keys (simulates key rotation)
      jwks_rotated = JWTHelper.build_jwks([ctx.public, public2])
      stub_jwks(jwks_rotated)

      # Should re-fetch and find the new key
      assert {:ok, _jwk} = KeySet.get_key(ctx.registration, kid2, req_options: req_options())
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
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      assert {:error, %Ltix.Errors.Unknown.Unknown{}} =
               KeySet.get_key(ctx.registration, ctx.kid,
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
               KeySet.get_key(ctx.registration, ctx.kid, req_options: req_options())
    end

    test "returns Unknown error on network failure", ctx do
      Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, %Ltix.Errors.Unknown.Unknown{}} =
               KeySet.get_key(ctx.registration, ctx.kid,
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

      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.kid, opts)
      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.kid, opts)
      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.kid, opts)

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

      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.kid, opts)
      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.kid, opts)

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

      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.kid, opts)
      assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.kid, opts)

      # Default max-age applies, so only one fetch
      assert :counters.get(fetch_count, 1) == 1
    end
  end

  defp stub_jwks(jwks, cache_control \\ "max-age=300") do
    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", cache_control)
      |> Req.Test.json(jwks)
    end)
  end

  defp req_options do
    [plug: {Req.Test, Ltix.JWT.KeySet}]
  end
end
