defmodule Msg.Integration.UsersTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Msg.{Client, Users}

  setup_all do
    creds = %{
      client_id: System.fetch_env!("MICROSOFT_CLIENT_ID"),
      client_secret: System.fetch_env!("MICROSOFT_CLIENT_SECRET"),
      tenant_id: System.fetch_env!("MICROSOFT_TENANT_ID")
    }

    client = Client.new(creds)

    {:ok, client: client}
  end

  test "lists all users", %{client: client} do
    {:ok, users} = Users.list(client)

    assert is_list(users)
    assert length(users) > 0
    # Verify structure of user objects
    first_user = List.first(users)
    assert is_map(first_user)
    assert Map.has_key?(first_user, "id")
  end
end
