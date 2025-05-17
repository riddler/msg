defmodule Msg.ClientTest do
  use ExUnit.Case, async: true

  @creds %{
    client_id: "fake-client-id",
    client_secret: "fake-client-secret",
    tenant_id: "fake-tenant-id"
  }

  test "new/2 builds a Req client with expected headers" do
    token_provider = fn _ -> "stub-token-123" end

    client = Msg.Client.new(@creds, token_provider)
    headers = Req.get_headers_list(client)

    assert client.url == URI.parse("https://graph.microsoft.com/v1.0")
    assert {"authorization", "Bearer stub-token-123"} in headers
    assert {"content-type", "application/json"} in headers
    assert {"accept", "application/json"} in headers
  end
end
