defmodule Msg.Integration.ExtensionsTest do
  use ExUnit.Case, async: false

  alias Msg.Calendar.Events
  alias Msg.Client
  alias Msg.Extensions

  @moduletag :integration

  setup do
    credentials = %{
      client_id: System.get_env("MICROSOFT_CLIENT_ID"),
      client_secret: System.get_env("MICROSOFT_CLIENT_SECRET"),
      tenant_id: System.get_env("MICROSOFT_TENANT_ID")
    }

    {:ok, credentials: credentials}
  end

  describe "Extension CRUD operations on calendar events" do
    setup %{credentials: credentials} do
      app_client = Client.new(credentials)
      user_email = System.get_env("MICROSOFT_SYSTEM_USER_EMAIL")

      if user_email do
        {:ok, app_client: app_client, user_email: user_email}
      else
        :ok
      end
    end

    test "create, get, delete extension lifecycle", %{
      app_client: app_client,
      user_email: user_email
    } do
      if app_client && user_email do
        # Create a test event
        event = %{
          subject: "Test Event for Extensions",
          start: %{
            date_time: "2025-06-10T10:00:00",
            time_zone: "Pacific Standard Time"
          },
          end: %{
            date_time: "2025-06-10T11:00:00",
            time_zone: "Pacific Standard Time"
          }
        }

        {:ok, created_event} = Events.create(app_client, event, user_id: user_email)
        event_id = created_event["id"]
        resource_path = "/users/#{user_email}/events/#{event_id}"
        extension_name = "com.example.integrationtest"

        # Create extension
        {:ok, created_ext} =
          Extensions.create(app_client, resource_path, extension_name, %{
            project_id: "test_proj_123",
            priority: "high",
            status: "pending"
          })

        assert created_ext["extensionName"] == extension_name
        assert created_ext["projectId"] == "test_proj_123"
        assert created_ext["priority"] == "high"
        assert created_ext["status"] == "pending"

        # Get extension
        {:ok, retrieved_ext} = Extensions.get(app_client, resource_path, extension_name)
        assert retrieved_ext["extensionName"] == extension_name
        assert retrieved_ext["projectId"] == "test_proj_123"
        assert retrieved_ext["priority"] == "high"

        # Note: Microsoft Graph does not support PATCH updates on open extensions
        # To update, you must delete and recreate the extension

        # Delete extension
        :ok = Extensions.delete(app_client, resource_path, extension_name)

        # Verify deletion
        assert {:error, :not_found} = Extensions.get(app_client, resource_path, extension_name)

        # Cleanup event
        :ok = Events.delete(app_client, event_id, user_id: user_email)
      else
        assert true
      end
    end

    test "returns not_found for non-existent extension", %{
      app_client: app_client,
      user_email: user_email
    } do
      if app_client && user_email do
        # Create a test event
        event = %{
          subject: "Test Event",
          start: %{
            date_time: "2025-06-11T10:00:00",
            time_zone: "Pacific Standard Time"
          },
          end: %{
            date_time: "2025-06-11T11:00:00",
            time_zone: "Pacific Standard Time"
          }
        }

        {:ok, created_event} = Events.create(app_client, event, user_id: user_email)
        event_id = created_event["id"]
        resource_path = "/users/#{user_email}/events/#{event_id}"

        # Try to get non-existent extension
        assert {:error, :not_found} =
                 Extensions.get(app_client, resource_path, "com.example.nonexistent")

        # Cleanup
        :ok = Events.delete(app_client, event_id, user_id: user_email)
      else
        assert true
      end
    end

    test "list extensions returns method_not_allowed for calendar events", %{
      app_client: app_client,
      user_email: user_email
    } do
      if app_client && user_email do
        # Create a test event
        event = %{
          subject: "Test Event for List",
          start: %{
            date_time: "2025-06-12T10:00:00",
            time_zone: "Pacific Standard Time"
          },
          end: %{
            date_time: "2025-06-12T11:00:00",
            time_zone: "Pacific Standard Time"
          }
        }

        {:ok, created_event} = Events.create(app_client, event, user_id: user_email)
        event_id = created_event["id"]
        resource_path = "/users/#{user_email}/events/#{event_id}"

        # Create an extension first
        {:ok, _} =
          Extensions.create(app_client, resource_path, "com.example.listtest", %{
            test_prop: "value"
          })

        # Try to list extensions (not supported for calendar events)
        result = Extensions.list(app_client, resource_path)
        assert match?({:error, :method_not_allowed}, result)

        # Cleanup
        :ok = Extensions.delete(app_client, resource_path, "com.example.listtest")
        :ok = Events.delete(app_client, event_id, user_id: user_email)
      else
        assert true
      end
    end
  end
end
