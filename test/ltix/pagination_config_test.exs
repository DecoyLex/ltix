defmodule Ltix.PaginationConfigTest do
  use ExUnit.Case, async: false

  alias Ltix.Pagination

  setup do
    previous = Application.get_env(:ltix, :req_options)
    Application.put_env(:ltix, :req_options, plug: {Req.Test, :ltix})

    on_exit(fn ->
      if previous == nil,
        do: Application.delete_env(:ltix, :req_options),
        else: Application.put_env(:ltix, :req_options, previous)
    end)
  end

  test "applies the application's req_options" do
    Req.Test.stub(Pagination, &Req.Test.json(&1, %{"page" => 1}))

    assert {:ok, pages} = Pagination.stream("https://example.com/api", [])
    assert Enum.to_list(pages) == [%{"page" => 1}]
  end

  test "caller req_options override the application's" do
    Req.Test.stub(:caller_stub, &Req.Test.json(&1, %{"page" => "caller"}))

    assert {:ok, pages} =
             Pagination.stream("https://example.com/api", [],
               req_options: [plug: {Req.Test, :caller_stub}]
             )

    assert Enum.to_list(pages) == [%{"page" => "caller"}]
  end
end
