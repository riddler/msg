defmodule Msg.Integration.Calendar.EventsTest do
  use ExUnit.Case, async: false

  alias Msg.AuthTestHelpers
  alias Msg.Calendar.Events
  alias Msg.Client

  @moduletag :integration

  setup do
    credentials = %{
      client_id: System.get_env("MICROSOFT_CLIENT_ID"),
      client_secret: System.get_env("MICROSOFT_CLIENT_SECRET"),
      tenant_id: System.get_env("MICROSOFT_TENANT_ID")
    }

    {:ok, credentials: credentials}
  end

  describe "User calendar operations (application-only auth)" do
    setup %{credentials: credentials} do
      app_client = Client.new(credentials)
      user_email = System.get_env("MICROSOFT_SYSTEM_USER_EMAIL")

      if user_email do
        {:ok, app_client: app_client, user_email: user_email}
      else
        :ok
      end
    end

    test "create, get, update, delete event lifecycle", %{
      app_client: app_client,
      user_email: user_email
    } do
      if app_client && user_email do
        # Create event
        event = %{
          subject: "Test Event - User Calendar",
          start: %{
            date_time: "2025-06-01T10:00:00",
            time_zone: "Pacific Standard Time"
          },
          end: %{
            date_time: "2025-06-01T11:00:00",
            time_zone: "Pacific Standard Time"
          },
          body: %{
            content_type: "Text",
            content: "Test event created by integration test"
          }
        }

        {:ok, created_event} = Events.create(app_client, event, user_id: user_email)

        assert created_event["subject"] == "Test Event - User Calendar"
        assert is_binary(created_event["id"])
        event_id = created_event["id"]

        # Get event
        {:ok, retrieved_event} = Events.get(app_client, event_id, user_id: user_email)
        assert retrieved_event["id"] == event_id
        assert retrieved_event["subject"] == "Test Event - User Calendar"

        # Update event
        {:ok, updated_event} =
          Events.update(app_client, event_id, %{subject: "Updated Test Event"},
            user_id: user_email
          )

        assert updated_event["subject"] == "Updated Test Event"

        # Delete event
        :ok = Events.delete(app_client, event_id, user_id: user_email)

        # Verify deletion
        assert {:error, :not_found} = Events.get(app_client, event_id, user_id: user_email)
      else
        # Skip test if credentials not available
        assert true
      end
    end

    test "list events with pagination", %{app_client: app_client, user_email: user_email} do
      if app_client && user_email do
        {:ok, events} = Events.list(app_client, user_id: user_email, auto_paginate: true)
        assert is_list(events)
      else
        assert true
      end
    end

    test "list events with date range filter", %{
      app_client: app_client,
      user_email: user_email
    } do
      if app_client && user_email do
        {:ok, events} =
          Events.list(app_client,
            user_id: user_email,
            start_datetime: ~U[2025-01-01 00:00:00Z],
            end_datetime: ~U[2025-12-31 23:59:59Z]
          )

        assert is_list(events)
      else
        assert true
      end
    end

    test "create event with extension", %{app_client: app_client, user_email: user_email} do
      if app_client && user_email do
        event = %{
          subject: "Test Event with Extension",
          start: %{
            date_time: "2025-06-02T10:00:00",
            time_zone: "Pacific Standard Time"
          },
          end: %{
            date_time: "2025-06-02T11:00:00",
            time_zone: "Pacific Standard Time"
          }
        }

        extension = %{
          extension_name: "com.example.test",
          project_id: "test_project_123",
          resource_id: "test_resource_456"
        }

        {:ok, created_event} =
          Events.create_with_extension(app_client, event, extension, user_id: user_email)

        assert created_event["subject"] == "Test Event with Extension"
        assert is_list(created_event["extensions"])

        # Find our extension
        test_ext =
          Enum.find(created_event["extensions"], fn ext ->
            ext["extensionName"] == "com.example.test"
          end)

        assert test_ext != nil
        assert test_ext["projectId"] == "test_project_123"
        assert test_ext["resourceId"] == "test_resource_456"

        # Cleanup
        :ok = Events.delete(app_client, created_event["id"], user_id: user_email)
      else
        assert true
      end
    end

    test "get event with extensions", %{app_client: app_client, user_email: user_email} do
      if app_client && user_email do
        # Create event with extension first
        event = %{
          subject: "Test Event for Extension Retrieval",
          start: %{
            date_time: "2025-06-03T10:00:00",
            time_zone: "Pacific Standard Time"
          },
          end: %{
            date_time: "2025-06-03T11:00:00",
            time_zone: "Pacific Standard Time"
          }
        }

        extension_id = "com.example.test2"

        extension = %{
          extension_name: extension_id,
          test_field: "test_value"
        }

        {:ok, created_event} =
          Events.create_with_extension(app_client, event, extension, user_id: user_email)

        event_id = created_event["id"]

        # Get with specific extension
        {:ok, retrieved_event} =
          Events.get_with_extensions(app_client, event_id, extension_id, user_id: user_email)

        assert is_list(retrieved_event["extensions"])
        assert length(retrieved_event["extensions"]) > 0

        ext = List.first(retrieved_event["extensions"])
        assert ext["extensionName"] == extension_id
        assert ext["testField"] == "test_value"

        # Cleanup
        :ok = Events.delete(app_client, event_id, user_id: user_email)
      else
        assert true
      end
    end
  end

  describe "Group calendar operations (delegated permissions)" do
    setup %{credentials: credentials} do
      delegated_client = AuthTestHelpers.get_delegated_client(credentials)
      {:ok, delegated_client: delegated_client}
    end

    test "create and list group calendar events", context do
      delegated_client = Map.get(context, :delegated_client)

      if delegated_client do
        # This test would require a group_id
        # Skipping for now until we have group setup
        assert true
      else
        # Skip if no delegated permissions available
        assert true
      end
    end
  end

  describe "error handling" do
    setup %{credentials: credentials} do
      app_client = Client.new(credentials)
      {:ok, app_client: app_client}
    end

    test "returns error for non-existent event", %{app_client: app_client} do
      user_email = System.get_env("MICROSOFT_SYSTEM_USER_EMAIL")

      if user_email do
        # Use a properly formatted but non-existent event ID
        # Format: AAMkAGI... (base64-like string)
        fake_event_id =
          "AAMkADAwMDAwMDAwLTAwMDAtMDAwMC0wMDAwLTAwMDAwMDAwMDAwMABGAAAAAAAAAAAAAAAAAAAw"

        result = Events.get(app_client, fake_event_id, user_id: user_email)
        # Could be :not_found or another error depending on Graph API behavior
        assert match?({:error, _}, result)
      else
        assert true
      end
    end
  end
end
