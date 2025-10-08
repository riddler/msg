defmodule Msg.ClientTest do
  use ExUnit.Case, async: true

  alias Msg.Client

  @creds %{
    client_id: "fake-client-id",
    client_secret: "fake-client-secret",
    tenant_id: "fake-tenant-id"
  }

  describe "new/2 with credentials and token provider" do
    test "builds a Req client with expected headers" do
      token_provider = fn _ -> "stub-token-123" end

      client = Client.new(@creds, token_provider)
      headers = Req.get_headers_list(client)

      assert client.options.base_url == "https://graph.microsoft.com/v1.0"
      assert {"authorization", "Bearer stub-token-123"} in headers
      assert {"content-type", "application/json"} in headers
      assert {"accept", "application/json"} in headers
    end
  end

  describe "new/1 with access token" do
    test "builds a Req client with provided access token" do
      access_token = "test-access-token-abc123"

      client = Client.new(access_token)
      headers = Req.get_headers_list(client)

      assert client.options.base_url == "https://graph.microsoft.com/v1.0"
      assert {"authorization", "Bearer test-access-token-abc123"} in headers
      assert {"content-type", "application/json"} in headers
      assert {"accept", "application/json"} in headers
    end

    test "does not call token provider when given access token" do
      # The second argument (token_provider) should be ignored when first arg is a string
      token_provider = fn _ -> raise "Should not be called!" end

      access_token = "direct-token"
      client = Client.new(access_token, token_provider)
      headers = Req.get_headers_list(client)

      assert {"authorization", "Bearer direct-token"} in headers
    end
  end

  # Note: Integration tests for refresh token flow are in
  # test/msg/integration/auth_test.exs
end
