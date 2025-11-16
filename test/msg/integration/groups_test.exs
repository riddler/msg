defmodule Msg.Integration.GroupsTest do
  use ExUnit.Case, async: false

  alias Msg.{Client, Groups}

  @moduletag :integration

  setup_all do
    creds = %{
      client_id: System.fetch_env!("MICROSOFT_CLIENT_ID"),
      client_secret: System.fetch_env!("MICROSOFT_CLIENT_SECRET"),
      tenant_id: System.fetch_env!("MICROSOFT_TENANT_ID")
    }

    test_group_id = System.fetch_env!("MICROSOFT_TEST_GROUP_ID")
    test_user_id = System.fetch_env!("MICROSOFT_TEST_USER_ID")
    other_test_user_id = System.fetch_env!("MICROSOFT_OTHER_TEST_USER_ID")

    client = Client.new(creds)

    {:ok,
     client: client,
     test_group_id: test_group_id,
     test_user_id: test_user_id,
     other_test_user_id: other_test_user_id}
  end

  test "gets a specific group", %{client: client, test_group_id: test_group_id} do
    {:ok, group} = Groups.get(client, test_group_id)

    assert group["id"] == test_group_id
    assert group["displayName"] == "Test Group"
    assert is_binary(group["id"])
  end

  test "lists all groups", %{client: client} do
    {:ok, groups} = Groups.list(client)

    assert is_list(groups)
    assert length(groups) > 0

    # Find our test group
    test_group = Enum.find(groups, fn g -> g["displayName"] == "Test Group" end)
    assert test_group != nil
  end

  test "lists groups with pagination disabled", %{client: client} do
    {:ok, result} = Groups.list(client, auto_paginate: false)

    assert is_map(result)
    assert Map.has_key?(result, :items)
    assert is_list(result.items)
  end

  test "lists groups with filter", %{client: client} do
    {:ok, groups} = Groups.list(client, filter: "startswith(displayName,'Test')")

    assert is_list(groups)
    # Should find at least our Test Group
    assert Enum.any?(groups, fn g -> g["displayName"] == "Test Group" end)
  end

  test "lists members of a group", %{client: client, test_group_id: test_group_id} do
    {:ok, members} = Groups.list_members(client, test_group_id)

    assert is_list(members)
    # Members list may be empty or contain users
  end

  test "adds and removes a member from a group", %{
    client: client,
    test_group_id: test_group_id,
    test_user_id: test_user_id
  } do
    # Add member
    assert :ok = Groups.add_member(client, test_group_id, test_user_id)

    # Verify member was added
    {:ok, members} = Groups.list_members(client, test_group_id)
    assert Enum.any?(members, fn m -> m["id"] == test_user_id end)

    # Remove member
    assert :ok = Groups.remove_member(client, test_group_id, test_user_id)

    # Verify member was removed
    {:ok, members_after} = Groups.list_members(client, test_group_id)
    refute Enum.any?(members_after, fn m -> m["id"] == test_user_id end)
  end

  test "creates a new group with snake_case attributes", %{client: client} do
    timestamp = System.system_time(:second)

    attrs = %{
      display_name: "Test Group Created #{timestamp}",
      mail_enabled: true,
      mail_nickname: "test-group-#{timestamp}",
      security_enabled: false,
      group_types: ["Unified"],
      description: "Temporary test group for integration tests",
      visibility: "Private"
    }

    {:ok, group} = Groups.create(client, attrs)

    assert is_binary(group["id"])
    assert group["displayName"] == "Test Group Created #{timestamp}"
    assert group["mailEnabled"] == true
    assert group["securityEnabled"] == false
    assert "Unified" in group["groupTypes"]

    # Clean up - delete the created group
    assert :ok = Groups.delete(client, group["id"])
  end

  test "handles error when getting non-existent group", %{client: client} do
    fake_id = "00000000-0000-0000-0000-000000000000"

    assert {:error, :not_found} = Groups.get(client, fake_id)
  end

  test "adds another member to a group", %{
    client: client,
    test_group_id: test_group_id,
    other_test_user_id: other_test_user_id
  } do
    # Add another member
    assert :ok = Groups.add_member(client, test_group_id, other_test_user_id)

    # Verify member was added
    {:ok, members} = Groups.list_members(client, test_group_id)
    assert Enum.any?(members, fn m -> m["id"] == other_test_user_id end)

    # Clean up - remove the member
    assert :ok = Groups.remove_member(client, test_group_id, other_test_user_id)
  end

  test "returns error when creating group with missing required fields", %{client: client} do
    # Missing mail_nickname and other required fields
    attrs = %{
      display_name: "Incomplete Group"
    }

    assert {:error, {:graph_api_error, %{status: 400}}} = Groups.create(client, attrs)
  end

  test "handles error when adding non-existent user as member", %{
    client: client,
    test_group_id: test_group_id
  } do
    fake_user_id = "00000000-0000-0000-0000-000000000000"

    result = Groups.add_member(client, test_group_id, fake_user_id)

    # Should get an error (404 or 400)
    assert {:error, _} = result
  end

  test "handles error when removing user that's not a member", %{
    client: client,
    test_group_id: test_group_id,
    other_test_user_id: other_test_user_id
  } do
    # Ensure user is not a member first
    {:ok, members} = Groups.list_members(client, test_group_id)

    unless Enum.any?(members, fn m -> m["id"] == other_test_user_id end) do
      # Try to remove user who isn't a member
      result = Groups.remove_member(client, test_group_id, other_test_user_id)

      # Should get an error (404)
      assert {:error, _} = result
    end
  end

  test "adds owner to a newly created group", %{
    client: client,
    other_test_user_id: other_test_user_id
  } do
    timestamp = System.system_time(:second)

    attrs = %{
      display_name: "Test Group for Owner #{timestamp}",
      mail_enabled: true,
      mail_nickname: "test-owner-#{timestamp}",
      security_enabled: false,
      group_types: ["Unified"],
      description: "Test group for owner addition"
    }

    {:ok, group} = Groups.create(client, attrs)

    # Add owner to the newly created group
    assert :ok = Groups.add_owner(client, group["id"], other_test_user_id)

    # Clean up
    assert :ok = Groups.delete(client, group["id"])
  end

  test "deletes a group successfully", %{client: client} do
    timestamp = System.system_time(:second)

    attrs = %{
      display_name: "Test Group to Delete #{timestamp}",
      mail_enabled: true,
      mail_nickname: "test-delete-#{timestamp}",
      security_enabled: false,
      group_types: ["Unified"],
      description: "Temporary test group for delete operation"
    }

    {:ok, group} = Groups.create(client, attrs)
    group_id = group["id"]

    # Delete the group
    assert :ok = Groups.delete(client, group_id)

    # Verify the group is deleted
    assert {:error, :not_found} = Groups.get(client, group_id)
  end

  test "handles error when deleting non-existent group", %{client: client} do
    fake_id = "00000000-0000-0000-0000-000000000000"

    assert {:error, :not_found} = Groups.delete(client, fake_id)
  end
end
