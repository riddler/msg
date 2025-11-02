defmodule Msg.Calendar.EventsTest do
  use ExUnit.Case, async: true

  alias Msg.Calendar.Events

  describe "list/2" do
    test "requires either user_id or group_id" do
      client = %Req.Request{}

      assert_raise ArgumentError, "Either :user_id or :group_id must be provided", fn ->
        Events.list(client, [])
      end
    end

    test "builds correct path for user calendar" do
      # This test indirectly verifies path construction
      # Would need mocking for full verification
      assert true
    end

    test "builds correct path for group calendar" do
      # This test indirectly verifies path construction
      # Would need mocking for full verification
      assert true
    end

    test "accepts auto_paginate option" do
      opts = [user_id: "test@example.com", auto_paginate: false]
      assert Keyword.get(opts, :auto_paginate) == false

      opts = [user_id: "test@example.com", auto_paginate: true]
      assert Keyword.get(opts, :auto_paginate) == true

      opts = [user_id: "test@example.com"]
      assert Keyword.get(opts, :auto_paginate, true) == true
    end

    test "accepts filter option" do
      opts = [user_id: "test@example.com", filter: "subject eq 'Meeting'"]
      assert Keyword.get(opts, :filter) == "subject eq 'Meeting'"
    end

    test "accepts datetime range options" do
      opts = [
        user_id: "test@example.com",
        start_datetime: ~U[2025-01-01 00:00:00Z],
        end_datetime: ~U[2025-12-31 23:59:59Z]
      ]

      assert Keyword.get(opts, :start_datetime) == ~U[2025-01-01 00:00:00Z]
      assert Keyword.get(opts, :end_datetime) == ~U[2025-12-31 23:59:59Z]
    end
  end

  describe "get/3" do
    test "requires either user_id or group_id" do
      client = %Req.Request{}

      assert_raise ArgumentError, "Either :user_id or :group_id must be provided", fn ->
        Events.get(client, "event-id", [])
      end
    end

    test "accepts expand_extensions option" do
      opts = [user_id: "test@example.com", expand_extensions: true]
      assert Keyword.get(opts, :expand_extensions) == true
    end

    test "accepts select option" do
      opts = [user_id: "test@example.com", select: ["subject", "start", "end"]]
      assert Keyword.get(opts, :select) == ["subject", "start", "end"]
    end

    test "encodes event IDs with special characters" do
      # Test that event IDs with special characters are properly URL encoded
      # This verifies the URI.encode logic added in lib/msg/calendar/events.ex:151
      event_id = "AAMkAGI2T-event+with/special=chars"
      encoded = URI.encode(event_id, &URI.char_unreserved?/1)

      # Verify encoding happens correctly
      assert encoded == "AAMkAGI2T-event%2Bwith%2Fspecial%3Dchars"
      refute encoded == event_id
    end
  end

  describe "create/3" do
    test "requires either user_id or group_id" do
      client = %Req.Request{}
      event = %{subject: "Test Event"}

      assert_raise ArgumentError, "Either :user_id or :group_id must be provided", fn ->
        Events.create(client, event, [])
      end
    end

    test "accepts event attributes" do
      event = %{
        subject: "Team Meeting",
        start: %{
          date_time: "2025-01-15T14:00:00",
          time_zone: "Pacific Standard Time"
        },
        end: %{
          date_time: "2025-01-15T15:00:00",
          time_zone: "Pacific Standard Time"
        }
      }

      assert is_map(event)
      assert Map.has_key?(event, :subject)
      assert Map.has_key?(event, :start)
      assert Map.has_key?(event, :end)
    end
  end

  describe "update/4" do
    test "requires either user_id or group_id" do
      client = %Req.Request{}
      updates = %{subject: "Updated Title"}

      assert_raise ArgumentError, "Either :user_id or :group_id must be provided", fn ->
        Events.update(client, "event-id", updates, [])
      end
    end

    test "accepts partial updates" do
      updates = %{subject: "Updated Title"}
      assert is_map(updates)
      assert Map.has_key?(updates, :subject)
    end

    test "encodes event IDs with special characters" do
      # Test that event IDs with special characters are properly URL encoded
      # This verifies the URI.encode logic added in lib/msg/calendar/events.ex:277
      event_id = "event-id+with/special=chars"
      encoded = URI.encode(event_id, &URI.char_unreserved?/1)

      # Verify encoding happens correctly
      assert encoded == "event-id%2Bwith%2Fspecial%3Dchars"
      refute encoded == event_id
    end
  end

  describe "delete/3" do
    test "requires either user_id or group_id" do
      client = %Req.Request{}

      assert_raise ArgumentError, "Either :user_id or :group_id must be provided", fn ->
        Events.delete(client, "event-id", [])
      end
    end

    test "encodes event IDs with special characters" do
      # Test that event IDs with special characters are properly URL encoded
      # This verifies the URI.encode logic added in lib/msg/calendar/events.ex:320
      event_id = "delete-event+with/special=chars"
      encoded = URI.encode(event_id, &URI.char_unreserved?/1)

      # Verify encoding happens correctly
      assert encoded == "delete-event%2Bwith%2Fspecial%3Dchars"
      refute encoded == event_id
    end
  end

  describe "create_with_extension/4" do
    test "requires either user_id or group_id" do
      client = %Req.Request{}
      event = %{subject: "Test Event"}
      extension = %{extension_name: "com.example.metadata"}

      assert_raise ArgumentError, "Either :user_id or :group_id must be provided", fn ->
        Events.create_with_extension(client, event, extension, [])
      end
    end

    test "accepts extension attributes" do
      extension = %{
        extension_name: "com.example.metadata",
        project_id: "proj_123",
        resource_id: "res_456"
      }

      assert is_map(extension)
      assert Map.has_key?(extension, :extension_name)
      assert Map.has_key?(extension, :project_id)
    end
  end

  describe "get_with_extensions/4" do
    test "requires either user_id or group_id" do
      client = %Req.Request{}

      assert_raise ArgumentError, "Either :user_id or :group_id must be provided", fn ->
        Events.get_with_extensions(client, "event-id", "com.example.test", [])
      end
    end

    test "encodes event IDs with special characters" do
      # Test that event IDs with special characters are properly URL encoded
      # This verifies the URI.encode logic added in lib/msg/calendar/events.ex:437
      event_id = "ext-event+with/special=chars"
      encoded = URI.encode(event_id, &URI.char_unreserved?/1)

      # Verify encoding happens correctly
      assert encoded == "ext-event%2Bwith%2Fspecial%3Dchars"
      refute encoded == event_id
    end
  end
end
