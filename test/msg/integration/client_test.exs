defmodule Msg.Integration.ClientTest do
  use ExUnit.Case, async: false

  alias Msg.Client

  @moduletag :integration

  test "creates a new client and fetches an access token" do
    creds = %{
      client_id: System.fetch_env!("MICROSOFT_CLIENT_ID"),
      client_secret: System.fetch_env!("MICROSOFT_CLIENT_SECRET"),
      tenant_id: System.fetch_env!("MICROSOFT_TENANT_ID")
    }

    # Ensure no errors are raised and token is returned
    token = Client.fetch_token!(creds)
    assert is_binary(token)
    assert String.length(token) > 20
  end
end
