defmodule Msg.SubscriptionsTest do
  use ExUnit.Case, async: true

  alias Msg.Subscriptions

  describe "validate_notification/2" do
    test "accepts valid notification with matching client state" do
      payload = %{
        "value" => [
          %{
            "subscriptionId" => "sub-123",
            "clientState" => "secret-token",
            "changeType" => "created",
            "resource" => "users/test@example.com/events/event-123"
          }
        ]
      }

      assert :ok = Subscriptions.validate_notification(payload, "secret-token")
    end

    test "rejects notification with mismatched client state" do
      payload = %{
        "value" => [%{"clientState" => "wrong-token"}]
      }

      assert {:error, :invalid_client_state} =
               Subscriptions.validate_notification(payload, "correct-token")
    end

    test "accepts notification with no client state if none expected" do
      payload = %{"value" => [%{"subscriptionId" => "sub-123"}]}

      assert :ok = Subscriptions.validate_notification(payload, nil)
    end

    test "rejects invalid payload structure" do
      assert {:error, :invalid_payload} = Subscriptions.validate_notification(%{}, "token")
    end

    test "accepts notification when multiple notifications present" do
      payload = %{
        "value" => [
          %{"subscriptionId" => "sub-1", "clientState" => "token-1"},
          %{"subscriptionId" => "sub-2", "clientState" => "token-2"}
        ]
      }

      # Validates first notification's client state
      assert :ok = Subscriptions.validate_notification(payload, "token-1")
    end
  end

  describe "parse_notification/1" do
    test "parses single notification" do
      payload = %{
        "value" => [
          %{
            "subscriptionId" => "sub-123",
            "clientState" => "token",
            "changeType" => "updated",
            "resource" => "users/test@example.com/events/event-123",
            "resourceData" => %{
              "@odata.type" => "#Microsoft.Graph.Event",
              "id" => "event-123"
            }
          }
        ]
      }

      [notification] = Subscriptions.parse_notification(payload)

      assert notification.subscription_id == "sub-123"
      assert notification.client_state == "token"
      assert notification.change_type == "updated"
      assert notification.resource == "users/test@example.com/events/event-123"
      assert notification.resource_data["id"] == "event-123"
      assert notification.resource_data["@odata.type"] == "#Microsoft.Graph.Event"
    end

    test "parses multiple notifications in single payload" do
      payload = %{
        "value" => [
          %{
            "subscriptionId" => "sub-1",
            "changeType" => "created",
            "resource" => "resource-1",
            "resourceData" => %{}
          },
          %{
            "subscriptionId" => "sub-2",
            "changeType" => "updated",
            "resource" => "resource-2",
            "resourceData" => %{}
          },
          %{
            "subscriptionId" => "sub-3",
            "changeType" => "deleted",
            "resource" => "resource-3",
            "resourceData" => %{}
          }
        ]
      }

      notifications = Subscriptions.parse_notification(payload)

      assert length(notifications) == 3
      assert Enum.map(notifications, & &1.change_type) == ["created", "updated", "deleted"]
      assert Enum.map(notifications, & &1.subscription_id) == ["sub-1", "sub-2", "sub-3"]
    end

    test "handles empty value array" do
      payload = %{"value" => []}

      assert [] = Subscriptions.parse_notification(payload)
    end

    test "handles missing value key" do
      payload = %{}

      assert [] = Subscriptions.parse_notification(payload)
    end

    test "handles notification with missing optional fields" do
      payload = %{
        "value" => [
          %{
            "subscriptionId" => "sub-123",
            "changeType" => "created",
            "resource" => "users/test@example.com/events/event-123",
            "resourceData" => %{"id" => "event-123"}
            # No clientState
          }
        ]
      }

      [notification] = Subscriptions.parse_notification(payload)

      assert notification.subscription_id == "sub-123"
      assert notification.client_state == nil
      assert notification.change_type == "created"
    end
  end

  describe "DateTime conversion" do
    test "converts DateTime struct to ISO8601 string" do
      dt = ~U[2025-01-15 10:00:00Z]

      # Test DateTime has to_iso8601
      assert DateTime.to_iso8601(dt) == "2025-01-15T10:00:00Z"
    end

    test "handles different DateTime formats" do
      dt1 = ~U[2025-12-31 23:59:59Z]
      dt2 = DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second)

      assert is_binary(DateTime.to_iso8601(dt1))
      assert is_binary(DateTime.to_iso8601(dt2))
    end
  end
end
