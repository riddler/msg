defmodule Msg.Integration.Planner.TasksTest do
  use ExUnit.Case, async: false

  alias Msg.AuthTestHelpers
  alias Msg.Client
  alias Msg.Groups
  alias Msg.Planner.{Plans, Tasks}

  @moduletag :integration

  setup do
    credentials = %{
      client_id: System.get_env("MICROSOFT_CLIENT_ID"),
      client_secret: System.get_env("MICROSOFT_CLIENT_SECRET"),
      tenant_id: System.get_env("MICROSOFT_TENANT_ID")
    }

    {:ok, credentials: credentials}
  end

  describe "Task CRUD operations (delegated permissions)" do
    setup %{credentials: credentials} do
      delegated_client = AuthTestHelpers.get_delegated_client(credentials)
      app_client = Client.new(credentials)

      if delegated_client && app_client do
        # Create a test group and plan for tasks
        group = %{
          display_name: "Test Group for Tasks #{System.unique_integer([:positive])}",
          mail_enabled: true,
          mail_nickname: "tasks-test-#{System.unique_integer([:positive])}",
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

        {:ok, plan} =
          Plans.create(delegated_client, %{
            owner: group_id,
            title: "Test Plan for Tasks"
          })

        plan_id = plan["id"]

        on_exit(fn ->
          # Cleanup plan (which will cleanup tasks)
          if delegated_client do
            case Plans.get(delegated_client, plan_id) do
              {:ok, current_plan} ->
                Plans.delete(delegated_client, plan_id, current_plan["@odata.etag"])

              _ ->
                :ok
            end
          end
        end)

        {:ok, delegated_client: delegated_client, plan_id: plan_id}
      else
        {:ok, delegated_client: nil, plan_id: nil}
      end
    end

    test "create, get, update, delete task lifecycle", %{
      delegated_client: delegated_client,
      plan_id: plan_id
    } do
      if delegated_client && plan_id do
        # Create task
        {:ok, created_task} =
          Tasks.create(delegated_client, %{
            plan_id: plan_id,
            title: "Test Task for Integration",
            due_date_time: "2025-06-15T17:00:00Z"
          })

        assert created_task["title"] == "Test Task for Integration"
        assert created_task["planId"] == plan_id
        assert is_binary(created_task["id"])
        assert is_binary(created_task["@odata.etag"])

        task_id = created_task["id"]
        original_etag = created_task["@odata.etag"]

        # Get task
        {:ok, retrieved_task} = Tasks.get(delegated_client, task_id)
        assert retrieved_task["id"] == task_id
        assert retrieved_task["title"] == "Test Task for Integration"

        # Update task with correct etag
        {:ok, updated_task} =
          Tasks.update(delegated_client, task_id, %{percent_complete: 50}, etag: original_etag)

        assert updated_task["percentComplete"] == 50
        assert updated_task["@odata.etag"] != original_etag

        new_etag = updated_task["@odata.etag"]

        # Test etag mismatch
        result =
          Tasks.update(delegated_client, task_id, %{percent_complete: 75}, etag: original_etag)

        assert {:error, {:etag_mismatch, current_etag}} = result
        assert current_etag == new_etag

        # Delete task with correct etag
        :ok = Tasks.delete(delegated_client, task_id, new_etag)

        # Verify deletion
        assert {:error, :not_found} = Tasks.get(delegated_client, task_id)
      else
        assert true
      end
    end

    test "list tasks in a plan", %{delegated_client: delegated_client, plan_id: plan_id} do
      if delegated_client && plan_id do
        # Create a task
        {:ok, task} =
          Tasks.create(delegated_client, %{
            plan_id: plan_id,
            title: "Task for List Test"
          })

        task_id = task["id"]

        # List tasks in the plan
        {:ok, tasks} = Tasks.list_by_plan(delegated_client, plan_id)

        assert is_list(tasks)
        assert Enum.any?(tasks, fn t -> t["id"] == task_id end)

        # Cleanup
        :ok = Tasks.delete(delegated_client, task_id, task["@odata.etag"])
      else
        assert true
      end
    end

    test "task with metadata embedding and parsing", %{
      delegated_client: delegated_client,
      plan_id: plan_id
    } do
      if delegated_client && plan_id do
        # Create task description with embedded metadata
        metadata = %{
          project_id: "proj_integration_123",
          resource_id: "res_integration_456",
          organization_id: "org_integration_789"
        }

        description = Tasks.embed_metadata("Complete the integration test deliverable", metadata)

        {:ok, task} =
          Tasks.create(delegated_client, %{
            plan_id: plan_id,
            title: "Task with Metadata",
            description: description
          })

        task_id = task["id"]

        # Get task and verify metadata
        {:ok, retrieved_task} = Tasks.get(delegated_client, task_id)

        # Parse metadata from description
        parsed_metadata = Tasks.parse_metadata(retrieved_task["description"])

        assert parsed_metadata == metadata
        assert parsed_metadata[:project_id] == "proj_integration_123"
        assert parsed_metadata[:resource_id] == "res_integration_456"
        assert parsed_metadata[:organization_id] == "org_integration_789"

        # Update task with new metadata
        new_metadata = %{
          project_id: "proj_updated_999",
          resource_id: "res_updated_888"
        }

        updated_description = Tasks.embed_metadata("Updated task description", new_metadata)

        {:ok, updated_task} =
          Tasks.update(delegated_client, task_id, %{description: updated_description},
            etag: task["@odata.etag"]
          )

        # Verify new metadata
        parsed_new_metadata = Tasks.parse_metadata(updated_task["description"])
        assert parsed_new_metadata == new_metadata

        # Cleanup
        :ok = Tasks.delete(delegated_client, task_id, updated_task["@odata.etag"])
      else
        assert true
      end
    end
  end

  describe "User tasks (application-only auth)" do
    setup %{credentials: credentials} do
      app_client = Client.new(credentials)
      delegated_client = AuthTestHelpers.get_delegated_client(credentials)
      user_email = System.get_env("MICROSOFT_SYSTEM_USER_EMAIL")

      if delegated_client && user_email do
        # Create a plan for user tasks
        group = %{
          display_name: "Test Group for User Tasks #{System.unique_integer([:positive])}",
          mail_enabled: true,
          mail_nickname: "user-tasks-#{System.unique_integer([:positive])}",
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

        {:ok, plan} =
          Plans.create(delegated_client, %{
            owner: group_id,
            title: "Test Plan for User Tasks"
          })

        on_exit(fn ->
          if delegated_client do
            case Plans.get(delegated_client, plan["id"]) do
              {:ok, current_plan} ->
                Plans.delete(delegated_client, plan["id"], current_plan["@odata.etag"])

              _ ->
                :ok
            end
          end
        end)

        {:ok,
         app_client: app_client,
         delegated_client: delegated_client,
         plan: plan,
         user_email: user_email}
      else
        {:ok, app_client: nil, delegated_client: nil, plan: nil, user_email: nil}
      end
    end

    test "list tasks assigned to user", %{
      app_client: app_client,
      delegated_client: delegated_client,
      plan: plan,
      user_email: user_email
    } do
      if app_client && delegated_client && plan && user_email do
        # Create a task (requires delegated for group plan)
        {:ok, task} =
          Tasks.create(delegated_client, %{
            plan_id: plan["id"],
            title: "User Task Test"
          })

        # List tasks for user (can use app-only client)
        {:ok, tasks} = Tasks.list_by_user(app_client, user_id: user_email)

        assert is_list(tasks)
        # Note: The task might not appear immediately or might not be assigned to this user

        # Cleanup
        :ok = Tasks.delete(delegated_client, task["id"], task["@odata.etag"])
      else
        assert true
      end
    end
  end
end
