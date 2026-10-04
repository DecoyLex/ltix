defmodule Ltix.JWKConfigTest do
  use ExUnit.Case, async: false

  alias Ltix.JWK

  setup do
    previous = Application.fetch_env(:ltix, :default_key_size)

    on_exit(fn ->
      case previous do
        {:ok, size} -> Application.put_env(:ltix, :default_key_size, size)
        :error -> Application.delete_env(:ltix, :default_key_size)
      end
    end)
  end

  test "generate/1 uses the configured default key size" do
    Application.put_env(:ltix, :default_key_size, 3072)

    assert modulus_bits(JWK.generate()) == 3072
  end

  defp modulus_bits(%JWK{private_key_pem: pem}) do
    [entry] = :public_key.pem_decode(pem)
    modulus = elem(:public_key.pem_entry_decode(entry), 2)
    byte_size(:binary.encode_unsigned(modulus)) * 8
  end
end
