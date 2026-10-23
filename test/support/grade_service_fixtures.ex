defmodule GradeServiceFixtures do
  @moduledoc false

  alias Ltix.GradeService
  alias Ltix.GradeService.Endpoint

  @scopes [
    "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
    "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly",
    "https://purl.imsglobal.org/spec/lti-ags/scope/score"
  ]

  def scopes, do: @scopes

  def line_items_url, do: "https://platform.example.com/context/2923/lineitems"
  def line_item_url, do: line_items_url() <> "/1/lineitem"

  def endpoint,
    do: Endpoint.new!(line_items: line_items_url(), line_item: line_item_url(), scopes: @scopes)

  # A client for the grade service endpoint. Its options are the `:plugins`
  # list (defaults to `[]`), the granted `:scopes` (defaults to every grade
  # service scope), the `:endpoint`, and when the token `:expires_at`.
  def create_client(opts \\ []) do
    {endpoint, opts} = Keyword.pop_lazy(opts, :endpoint, &endpoint/0)

    TestClient.build(
      Ltix.Test.setup_platform!().registration,
      %{GradeService => endpoint},
      Keyword.merge(
        [scopes: @scopes, req_options: [plug: {Req.Test, GradeService}, retry: false]],
        opts
      )
    )
  end

  # Responds to each request with the JSON `respond` returns for the
  # request's method and decoded body, or with no content when it returns
  # `nil`. Sends `{method, body}` to the calling process.
  def stub_requests(respond) do
    owner = self()
    json = Ltix.AppConfig.json_library!()

    Req.Test.stub(GradeService, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = if body == "", do: nil, else: json.decode!(body)
      send(owner, {conn.method, body})

      case respond.(conn.method, body) do
        nil -> Plug.Conn.send_resp(conn, 204, "")
        response -> Req.Test.json(conn, response)
      end
    end)
  end
end
