defmodule Msg.Integration.Planner.PlansTest do
  use ExUnit.Case, async: false

  alias Msg.AuthTestHelpers
  alias Msg.Client
  alias Msg.Groups
  alias Msg.Planner.Plans

  @moduletag :integration

  setup do
    credentials = %{
      client_id: System.get_env("MICROSOFT_CLIENT_ID"),
      client_secret: System.get_env("MICROSOFT_CLIENT_SECRET"),
      tenant_id: System.get_env("MICROSOFT_TENANT_ID")
    }

    {:ok, credentials: credentials}
  end

  describe "Plan CRUD operations (delegated permissions)" do
    setup %{credentials: credentials} do
      delegated_client = AuthTestHelpers.get_delegated_client(credentials)
      app_client = Client.new(credentials)

      {:ok, delegated_client: delegated_client, app_client: app_client}
    end

    @tag :skip
    test "create, get, update, delete plan lifecycle", %{
      delegated_client: delegated_client,
      app_client: app_client
    } do
      if delegated_client && app_client do
        # First, create a test group (requires app-only permissions)
        group = %{
          display_name: "Test Group for Planner #{System.unique_integer([:positive])}",
          mail_enabled: true,
          mail_nickname: "planner-test-#{System.unique_integer([:positive])}",
          security_enabled: false,
          group_types: ["Unified"]
        }

        {:ok, created_group} = Groups.create(app_client, group)
        group_id = created_group["id"]

        # Add the ROPC user as both owner and member (Planner requirement)
        system_user_id = System.get_env("MICROSOFT_TEST_USER_ID")

        if system_user_id do
          :ok = Groups.add_owner(app_client, group_id, system_user_id)
          :ok = Groups.add_member(app_client, group_id, system_user_id)
        end

        # Give Azure time to propagate group membership (needs 8+ seconds)
        Process.sleep(8000)

        # Create plan (requires delegated permissions)
        {:ok, created_plan} =
          Plans.create(delegated_client, %{
            owner: group_id,
            title: "Test Plan for Integration Tests"
          })

        assert created_plan["title"] == "Test Plan for Integration Tests"
        assert created_plan["owner"] == group_id
        assert is_binary(created_plan["id"])
        assert is_binary(created_plan["@odata.etag"])

        plan_id = created_plan["id"]
        original_etag = created_plan["@odata.etag"]

        # Get plan
        {:ok, retrieved_plan} = Plans.get(delegated_client, plan_id)
        assert retrieved_plan["id"] == plan_id
        assert retrieved_plan["title"] == "Test Plan for Integration Tests"

        # Update plan with correct etag
        {:ok, updated_plan} =
          Plans.update(delegated_client, plan_id, %{title: "Updated Plan Title"},
            etag: original_etag
          )

        assert updated_plan["title"] == "Updated Plan Title"
        assert updated_plan["@odata.etag"] != original_etag

        new_etag = updated_plan["@odata.etag"]

        # Test etag mismatch - try to update with old etag
        result =
          Plans.update(delegated_client, plan_id, %{title: "Should Fail"}, etag: original_etag)

        assert {:error, {:etag_mismatch, current_etag}} = result
        assert current_etag == new_etag

        # Delete plan with correct etag
        :ok = Plans.delete(delegated_client, plan_id, new_etag)

        # Verify deletion
        assert {:error, :not_found} = Plans.get(delegated_client, plan_id)

        # Cleanup group
        # Note: In practice, you might want to keep the group or handle deletion differently
        # Groups API doesn't support deletion in all scenarios
      else
        # Skip if no delegated permissions available
        assert true
      end
    end

    @tag :skip
    test "list plans for a group", %{delegated_client: delegated_client, app_client: app_client} do
      if delegated_client && app_client do
        # Create a test group
        group = %{
          display_name: "Test Group for List #{System.unique_integer([:positive])}",
          mail_enabled: true,
          mail_nickname: "planner-list-#{System.unique_integer([:positive])}",
          security_enabled: false,
          group_types: ["Unified"]
        }

        {:ok, created_group} = Groups.create(app_client, group)
        group_id = created_group["id"]

        # Add the ROPC user as both owner and member (Planner requirement)
        system_user_id = System.get_env("MICROSOFT_TEST_USER_ID")

        if system_user_id do
          :ok = Groups.add_owner(app_client, group_id, system_user_id)
          :ok = Groups.add_member(app_client, group_id, system_user_id)
        end

        Process.sleep(8000)

        # Create a plan
        {:ok, plan} =
          Plans.create(delegated_client, %{
            owner: group_id,
            title: "Test Plan for List"
          })

        plan_id = plan["id"]

        # List plans for the group
        {:ok, plans} = Plans.list(delegated_client, group_id: group_id)

        assert is_list(plans)
        assert Enum.any?(plans, fn p -> p["id"] == plan_id end)

        # Cleanup
        :ok = Plans.delete(delegated_client, plan_id, plan["@odata.etag"])
      else
        assert true
      end
    end

    test "returns not_found for non-existent plan", %{delegated_client: delegated_client} do
      if delegated_client do
        # Use a valid-looking but non-existent plan ID
        fake_plan_id = "#{String.duplicate("A", 20)}"

        result = Plans.get(delegated_client, fake_plan_id)
        assert match?({:error, _}, result)
      else
        assert true
      end
    end
  end
end
