defmodule Ltix.JWT.KeySetTest do
  use ExUnit.Case, async: true

  alias Ltix.Errors.Unknown.TransportError
  alias Ltix.JWT.KeySet

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
        jwks_uri: "https://platform.example.com/.well-known/jwks-#{unique_id}.json"
      })

    %{registration: registration, platform_jwk: platform_jwk, jwks: jwks}
  end

  describe "get_key/3" do
    test "raises on unknown and invalid options", ctx do
      assert_raise Ltix.Errors.Invalid.InvalidOption, "Option :request_options is unknown", fn ->
        KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, request_options: [])
      end

      assert_raise Ltix.Errors.Invalid.InvalidOption, ~r/Option :key_set is invalid/, fn ->
        KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, key_set: "keys")
      end
    end

    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "fetches and selects key by kid", ctx do
      count_fetches(jwks(ctx.jwks))

      kid = ctx.platform_jwk.kid

      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
               KeySet.get_key(ctx.registration, kid, req_options: req_options())
    end

    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "selects correct key from multi-key JWKS", ctx do
      second_jwk = Ltix.JWK.generate()
      jwks = Ltix.JWK.to_jwks([ctx.platform_jwk, second_jwk])
      count_fetches(jwks(jwks))

      kid = second_jwk.kid

      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
               KeySet.get_key(ctx.registration, kid, req_options: req_options())
    end

    # [Cert §6.1.1] "Incorrect KID in JWT header"
    test "returns KidNotFound when kid not in JWKS", ctx do
      count_fetches(jwks(ctx.jwks))

      assert {:error, %Ltix.Errors.Security.KidNotFound{kid: "wrong-kid"}} =
               KeySet.get_key(ctx.registration, "wrong-kid", req_options: req_options())
    end

    # [Sec §6.4](https://www.imsglobal.org/spec/security/v1p0/#issuer-public-key-rotation)
    test "re-fetches an unknown kid once the refetch interval has passed", ctx do
      rotated_jwk = Ltix.JWK.generate()
      opts = cache_keys(ctx, refetch_interval: 0)
      fetch_count = count_fetches(jwks(Ltix.JWK.to_jwks([ctx.platform_jwk, rotated_jwk])))

      kid = rotated_jwk.kid

      for _lookup <- 1..2 do
        assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
                 KeySet.get_key(ctx.registration, kid, opts)
      end

      assert :counters.get(fetch_count, 1) == 1
    end

    # [Sec §6.4](https://www.imsglobal.org/spec/security/v1p0/#issuer-public-key-rotation)
    test "does not re-fetch an unknown kid within 30 seconds of the last fetch", ctx do
      fetch_count = count_fetches(jwks(ctx.jwks))
      opts = [req_options: req_options()]

      assert {:ok, _jwk} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)

      for kid <- ["unknown-kid-1", "unknown-kid-2"] do
        assert {:error, %Ltix.Errors.Security.KidNotFound{kid: ^kid}} =
                 KeySet.get_key(ctx.registration, kid, opts)
      end

      assert :counters.get(fetch_count, 1) == 1
    end

    test "does not re-fetch a kid missing from a key set it just fetched", ctx do
      fetch_count = count_fetches(jwks(ctx.jwks))

      assert {:error, %Ltix.Errors.Security.KidNotFound{}} =
               KeySet.get_key(ctx.registration, "unknown-kid", req_options: req_options())

      assert :counters.get(fetch_count, 1) == 1
    end

    test "keeps the cached keys when re-fetching for an unknown kid fails", ctx do
      opts = cache_keys(ctx, refetch_interval: 0)
      count_fetches(status(503))

      assert {:error, %TransportError{status: 503}} =
               KeySet.get_key(ctx.registration, "unknown-kid", opts)

      kid = ctx.platform_jwk.kid

      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
               KeySet.get_key(ctx.registration, kid, opts)
    end

    test "returns error for non-200 HTTP response", ctx do
      count_fetches(status(404))
      jwks_uri = ctx.registration.jwks_uri

      assert {:error, %TransportError{status: 404, url: ^jwks_uri, spec_ref: "Sec §6.3"}} =
               KeySet.get_key(ctx.registration, ctx.platform_jwk.kid,
                 req_options: req_options(retry: false)
               )
    end

    test "returns AccessDenied when the key set endpoint responds with HTTP 401", ctx do
      count_fetches(status(401))
      jwks_uri = ctx.registration.jwks_uri

      assert {:error,
              %Ltix.Errors.Security.AccessDenied{
                status: 401,
                url: ^jwks_uri,
                spec_ref: "Sec §6.3"
              }} =
               KeySet.get_key(ctx.registration, ctx.platform_jwk.kid,
                 req_options: req_options(retry: false)
               )
    end

    test "returns KidNotFound for a JWKS with no keys array", ctx do
      count_fetches(jwks(%{"not_keys" => []}))

      assert {:error, %Ltix.Errors.Security.KidNotFound{}} =
               KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, req_options: req_options())
    end

    test "skips malformed keys in the key set", ctx do
      [platform_key] = ctx.jwks["keys"]
      keys = [123, "key", %{"kid" => "no-type"}, %{"kty" => "RSA", "kid" => "bad", "n" => 1}]
      count_fetches(jwks(%{"keys" => keys ++ [platform_key]}))

      kid = ctx.platform_jwk.kid
      opts = [req_options: req_options()]

      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
               KeySet.get_key(ctx.registration, kid, opts)

      for kid <- ["no-type", "bad"] do
        assert {:error, %Ltix.Errors.Security.KidNotFound{kid: ^kid}} =
                 KeySet.get_key(ctx.registration, kid, opts)
      end
    end

    test "decodes a key set served without a JSON content type", ctx do
      body = Ltix.AppConfig.json_library!().encode!(ctx.jwks)
      kid = ctx.platform_jwk.kid

      for content_type <- ["text/plain", nil] do
        count_fetches(fn conn ->
          conn =
            if content_type,
              do: Plug.Conn.put_resp_content_type(conn, content_type),
              else: conn

          Plug.Conn.send_resp(conn, 200, body)
        end)

        opts = [key_set: start_key_set(refetch_interval: 0), req_options: req_options()]

        assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} =
                 KeySet.get_key(ctx.registration, kid, opts)

        stop_supervised!(__MODULE__.Keys)
      end
    end

    test "returns MalformedResponse for a key set that is not JSON", ctx do
      count_fetches(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<html>maintenance</html>")
      end)

      assert {:error, %Ltix.Errors.Invalid.MalformedResponse{service: KeySet}} =
               KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, req_options: req_options())
    end

    test "returns TransportError on network failure", ctx do
      count_fetches(&Req.Test.transport_error(&1, :timeout))
      jwks_uri = ctx.registration.jwks_uri

      assert {:error, %TransportError{status: nil, url: ^jwks_uri}} =
               KeySet.get_key(ctx.registration, ctx.platform_jwk.kid,
                 req_options: req_options(retry: false)
               )
    end

    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "caches JWKS and serves from cache on subsequent calls", ctx do
      fetch_count = count_fetches(jwks(ctx.jwks))
      opts = [req_options: req_options()]

      for _lookup <- 1..3 do
        assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)
      end

      assert :counters.get(fetch_count, 1) == 1
    end

    test "keeps a key set served with max-age=0 for the refetch interval", ctx do
      fetch_count = count_fetches(jwks(ctx.jwks, "max-age=0"))
      opts = [req_options: req_options()]

      for _lookup <- 1..2 do
        assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)
      end

      assert :counters.get(fetch_count, 1) == 1
    end

    # [Sec §6.3](https://www.imsglobal.org/spec/security/v1p0/#h_key-set-url)
    test "uses default max-age when no cache-control header", ctx do
      fetch_count =
        count_fetches(fn conn ->
          conn
          |> Plug.Conn.delete_resp_header("cache-control")
          |> Req.Test.json(ctx.jwks)
        end)

      opts = [key_set: start_key_set(refetch_interval: 0), req_options: req_options()]

      for _lookup <- 1..2 do
        assert {:ok, _} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)
      end

      assert :counters.get(fetch_count, 1) == 1
    end
  end

  describe "get_key/3 with lookups at the same time" do
    test "fetches a key set once for lookups that miss the cache together", ctx do
      fetch_count = count_fetches(jwks(ctx.jwks), delay: 100)
      kid = ctx.platform_jwk.kid

      for result <- lookup_concurrently(ctx, kid, req_options: req_options()) do
        assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} = result
      end

      assert :counters.get(fetch_count, 1) == 1
    end

    test "re-fetches once for lookups of a rotated key", ctx do
      rotated_jwk = Ltix.JWK.generate()
      opts = cache_keys(ctx, refetch_interval: 0)

      fetch_count =
        count_fetches(jwks(Ltix.JWK.to_jwks([ctx.platform_jwk, rotated_jwk])), delay: 100)

      kid = rotated_jwk.kid

      for result <- lookup_concurrently(ctx, kid, opts) do
        assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} = result
      end

      assert :counters.get(fetch_count, 1) == 1
    end

    test "fetches again when the process that was fetching is killed", ctx do
      owner = self()
      kid = ctx.platform_jwk.kid

      fetch_count =
        count_fetches(fn conn ->
          send(owner, {:fetching, self()})

          receive do
            :respond -> Req.Test.json(conn, ctx.jwks)
          end
        end)

      lookup = fn -> KeySet.get_key(ctx.registration, kid, req_options: req_options()) end

      first = Task.async(lookup)
      assert_receive {:fetching, _first}
      second = Task.async(lookup)
      Process.sleep(50)
      Task.shutdown(first, :brutal_kill)

      assert_receive {:fetching, fetcher}
      send(fetcher, :respond)

      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} = Task.await(second)
      assert :counters.get(fetch_count, 1) == 2
    end

    test "fetches again when the fetch raises", ctx do
      owner = self()
      kid = ctx.platform_jwk.kid

      fetch_count =
        count_fetches(fn conn ->
          send(owner, {:fetching, self()})

          receive do
            :raise -> raise "fetch failed"
            :respond -> Req.Test.json(conn, ctx.jwks)
          end
        end)

      lookup = fn ->
        try do
          KeySet.get_key(ctx.registration, kid, req_options: req_options())
        rescue
          error in RuntimeError -> {:raised, error.message}
        end
      end

      first = Task.async(lookup)
      assert_receive {:fetching, first_fetcher}
      second = Task.async(lookup)
      Process.sleep(50)
      send(first_fetcher, :raise)

      assert_receive {:fetching, second_fetcher}
      send(second_fetcher, :respond)

      assert Task.await(first) == {:raised, "fetch failed"}
      assert {:ok, %JOSE.JWK{fields: %{"kid" => ^kid}}} = Task.await(second)
      assert :counters.get(fetch_count, 1) == 2
    end
  end

  describe "get_key/3 after a failed fetch" do
    test "returns the error without fetching again for 30 seconds", ctx do
      fetch_count = count_fetches(status(503))
      opts = [req_options: req_options(retry: false)]

      for _attempt <- 1..3 do
        assert {:error, %TransportError{status: 503}} =
                 KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)
      end

      assert :counters.get(fetch_count, 1) == 1
    end
  end

  # Stubs the key set endpoint with `respond` and counts the requests to it.
  defp count_fetches(respond, opts \\ []) do
    fetch_count = :counters.new(1, [:atomics])

    Req.Test.stub(Ltix.JWT.KeySet, fn conn ->
      :counters.add(fetch_count, 1, 1)
      Process.sleep(Keyword.get(opts, :delay, 0))
      respond.(conn)
    end)

    fetch_count
  end

  defp jwks(jwks, cache_control \\ "max-age=300") do
    fn conn ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", cache_control)
      |> Req.Test.json(jwks)
    end
  end

  defp status(status), do: &Plug.Conn.send_resp(&1, status, "")

  defp start_key_set(opts) do
    start_supervised!({KeySet, [name: __MODULE__.Keys] ++ opts})
    __MODULE__.Keys
  end

  # Fetches the test's platform key into a new key set and returns the
  # options for looking keys up in it.
  defp cache_keys(ctx, opts) do
    count_fetches(jwks(ctx.jwks))
    opts = [key_set: start_key_set(opts), req_options: req_options(retry: false)]
    {:ok, _jwk} = KeySet.get_key(ctx.registration, ctx.platform_jwk.kid, opts)
    opts
  end

  defp lookup_concurrently(ctx, kid, opts) do
    1..20
    |> Enum.map(fn _index ->
      Task.async(fn -> KeySet.get_key(ctx.registration, kid, opts) end)
    end)
    |> Task.await_many()
  end

  defp req_options(extra \\ []) do
    [plug: {Req.Test, Ltix.JWT.KeySet}] ++ extra
  end
end
