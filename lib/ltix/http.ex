defmodule Ltix.HTTP do
  @moduledoc false

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

  defp rewrite_test_plug(opts, stub_name) do
    case Keyword.get(opts, :plug) do
      {Req.Test, _} -> Keyword.put(opts, :plug, {Req.Test, stub_name})
      _ -> opts
    end
  end
end
