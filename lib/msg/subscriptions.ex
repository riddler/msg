defmodule Msg.Subscriptions do
  @moduledoc """
  Manage Microsoft Graph change notification subscriptions (webhooks).

  Subscriptions enable real-time notifications when Microsoft 365 resources change,
  eliminating the need for polling.

  ## Maximum Subscription Duration by Resource

  - Calendar events: 4230 minutes (~3 days)
  - Messages: 4230 minutes (~3 days)
  - Contacts: 4230 minutes (~3 days)
  - Group events: 4230 minutes (~3 days)
  - OneDrive items: 42300 minutes (~30 days)

  ## Webhook Validation

  When creating a subscription, Microsoft sends a validation request:

      GET https://your-app.com/webhook?validationToken=abc123

  Your endpoint must respond with the validation token as plain text within
  10 seconds, or the subscription creation will fail.

  ### Example validation endpoint (Phoenix):

      # router.ex
      get "/api/webhooks/microsoft", WebhookController, :validate
      post "/api/webhooks/microsoft", WebhookController, :webhook

      # webhook_controller.ex
      def validate(conn, %{"validationToken" => token}) do
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, token)
      end

  ## Notification Format

  Notifications arrive as HTTP POST with JSON body:

      {
        "value": [
          {
            "subscriptionId": "sub-id",
            "clientState": "secret-token",
            "changeType": "created",
            "resource": "users/user@contoso.com/events/AAMk...",
            "resourceData": {
              "@odata.type": "#Microsoft.Graph.Event",
              "@odata.id": "Users/user@contoso.com/Events/AAMk...",
              "id": "AAMk..."
            }
          }
        ]
      }

  ## Authentication Requirements

  - **User calendars:** `Calendars.ReadWrite` (application or delegated)
  - **Group calendars:** `Calendars.ReadWrite.Shared` (delegated only)
  - Same permissions as the resource being monitored

  ## Examples

      # Create subscription for user calendar
      {:ok, subscription} = Subscriptions.create(client, %{
        change_type: "created,updated,deleted",
        notification_url: "https://yourapp.com/api/webhooks/calendar",
        resource: "/users/user@contoso.com/events",
        expiration_date_time: DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second),
        client_state: "secret-validation-token"
      })

      # Renew before expiry
      {:ok, renewed} = Subscriptions.renew(client, subscription["id"], days: 3)

      # Validate incoming notification
      case Subscriptions.validate_notification(payload, "secret-validation-token") do
        :ok -> process_notification(payload)
        {:error, :invalid_client_state} -> reject_notification()
      end

      # Parse notification
      notifications = Subscriptions.parse_notification(payload)
      Enum.each(notifications, fn notif ->
        handle_change(notif.change_type, notif.resource)
      end)

  ## References

  - [Microsoft Graph Subscriptions](https://learn.microsoft.com/en-us/graph/api/resources/subscription)
  - [Webhook Notifications](https://learn.microsoft.com/en-us/graph/webhooks)
  - [Subscription Lifecycle](https://learn.microsoft.com/en-us/graph/webhooks-lifecycle)
  """

  alias Msg.Request

  @doc """
  Creates a new webhook subscription.

  **Important:** Your notification URL must be publicly accessible via HTTPS
  and respond to Microsoft's validation request within 10 seconds.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `subscription` - Map with subscription properties:
    - `:change_type` (required) - Comma-separated: "created,updated,deleted"
    - `:notification_url` (required) - HTTPS webhook endpoint
    - `:resource` (required) - Resource path (e.g., "/users/{id}/events")
    - `:expiration_date_time` (required) - DateTime struct for expiration
    - `:client_state` (optional but recommended) - Secret validation token

  ## Returns

  - `{:ok, subscription}` - Created subscription with ID
  - `{:error, {:missing_required_fields, fields}}` - Missing required fields
  - `{:error, {:validation_timeout, _}}` - Webhook validation failed (10s timeout)
  - `{:error, term}` - Other errors

  ## Examples

      # User calendar subscription
      {:ok, subscription} = Subscriptions.create(client, %{
        change_type: "created,updated,deleted",
        notification_url: "https://yourapp.com/api/webhooks/calendar",
        resource: "/users/user@contoso.com/events",
        expiration_date_time: DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second),
        client_state: "secret-token-\#{:crypto.strong_rand_bytes(16) |> Base.encode64()}"
      })

      # Group calendar subscription (requires delegated auth)
      {:ok, subscription} = Subscriptions.create(delegated_client, %{
        change_type: "created,updated",
        notification_url: "https://yourapp.com/webhooks",
        resource: "/groups/group-id/calendar/events",
        expiration_date_time: DateTime.add(DateTime.utc_now(), 2 * 24 * 60 * 60, :second),
        client_state: "group-calendar-secret"
      })
  """
  @spec create(Req.Request.t(), map()) :: {:ok, map()} | {:error, term()}
  def create(client, subscription) do
    # Convert DateTime to ISO8601 string if needed
    subscription = convert_datetime_fields(subscription)

    # Convert snake_case keys to camelCase
    subscription_data = Request.convert_keys(subscription)

    # Validate required fields
    with :ok <- validate_create_params(subscription_data) do
      case Req.post(client, url: "/subscriptions", json: subscription_data) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          {:ok, body}

        {:ok, %{status: 400, body: body}} ->
          # Likely validation timeout or invalid URL
          handle_create_error(body)

        {:ok, %{status: status, body: body}} ->
          handle_error(status, body)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Lists all active subscriptions for the authenticated application.

  ## Parameters

  - `client` - Authenticated Req.Request client

  ## Returns

  - `{:ok, [subscription]}` - List of active subscriptions (may be empty)
  - `{:error, term}` - Error

  ## Examples

      {:ok, subscriptions} = Subscriptions.list(client)

      Enum.each(subscriptions, fn sub ->
        IO.puts("Subscription: \#{sub["id"]}")
        IO.puts("Resource: \#{sub["resource"]}")
        IO.puts("Expires: \#{sub["expirationDateTime"]}")
      end)
  """
  @spec list(Req.Request.t()) :: {:ok, [map()]} | {:error, term()}
  def list(client) do
    case Request.get(client, "/subscriptions") do
      {:ok, %{"value" => subscriptions}} ->
        {:ok, subscriptions}

      {:ok, response} ->
        # Handle unexpected response format
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets details for a specific subscription.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `subscription_id` - Subscription ID

  ## Returns

  - `{:ok, subscription}` - Subscription details
  - `{:error, :not_found}` - Subscription doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, subscription} = Subscriptions.get(client, "sub-id-123")

      {:ok, expiration, _} = DateTime.from_iso8601(subscription["expirationDateTime"])
      if DateTime.diff(expiration, DateTime.utc_now(), :hour) < 2 do
        # Renew soon!
      end
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get(client, subscription_id) do
    case Request.get(client, "/subscriptions/#{subscription_id}") do
      {:ok, subscription} ->
        {:ok, subscription}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a subscription. Primarily used for renewal.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `subscription_id` - Subscription ID
  - `updates` - Map of fields to update (typically just `expiration_date_time`)

  ## Returns

  - `{:ok, subscription}` - Updated subscription
  - `{:error, :not_found}` - Subscription doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      # Extend subscription by 3 more days
      new_expiration = DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second)

      {:ok, updated} = Subscriptions.update(client, subscription_id, %{
        expiration_date_time: new_expiration
      })
  """
  @spec update(Req.Request.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update(client, subscription_id, updates) do
    # Convert DateTime if present
    updates = convert_datetime_fields(updates)

    # Convert to camelCase
    updates_converted = Request.convert_keys(updates)

    case Req.patch(client, url: "/subscriptions/#{subscription_id}", json: updates_converted) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a subscription, stopping all notifications.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `subscription_id` - Subscription ID

  ## Returns

  - `:ok` - Subscription deleted successfully
  - `{:error, term}` - Error (404 is treated as success)

  ## Examples

      :ok = Subscriptions.delete(client, subscription_id)
  """
  @spec delete(Req.Request.t(), String.t()) :: :ok | {:error, term()}
  def delete(client, subscription_id) do
    case Req.delete(client, url: "/subscriptions/#{subscription_id}") do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: 404}} ->
        # Already deleted or doesn't exist - treat as success
        :ok

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Renews a subscription by extending its expiration date.

  This is a convenience wrapper around `update/3` for the common renewal case.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `subscription_id` - Subscription ID
  - `opts` - Options:
    - `:days` - Number of days to extend (default: 3)

  ## Returns

  - `{:ok, subscription}` - Renewed subscription with new expiration
  - `{:error, term}` - Error

  ## Examples

      # Renew for 3 more days (default)
      {:ok, renewed} = Subscriptions.renew(client, subscription_id)

      # Renew for 2 days
      {:ok, renewed} = Subscriptions.renew(client, subscription_id, days: 2)

      # Renew for maximum duration (30 days for OneDrive)
      {:ok, renewed} = Subscriptions.renew(client, subscription_id, days: 29)
  """
  @spec renew(Req.Request.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def renew(client, subscription_id, opts \\ []) do
    days = Keyword.get(opts, :days, 3)
    new_expiration = DateTime.add(DateTime.utc_now(), days * 24 * 60 * 60, :second)

    update(client, subscription_id, %{expiration_date_time: new_expiration})
  end

  @doc """
  Validates an incoming webhook notification.

  Checks that the `clientState` in the notification matches the expected value.
  This prevents accepting forged notifications.

  ## Parameters

  - `notification_payload` - The JSON payload from Microsoft's POST request
  - `expected_client_state` - The client state you provided when creating subscription

  ## Returns

  - `:ok` - Notification is valid
  - `{:error, :invalid_client_state}` - Client state doesn't match
  - `{:error, :invalid_payload}` - Payload structure is invalid

  ## Examples

      # In your webhook handler
      def handle_webhook(conn, params) do
        case Subscriptions.validate_notification(params, "my-secret-token") do
          :ok ->
            # Process notification
            notifications = Subscriptions.parse_notification(params)
            handle_notifications(notifications)
            send_resp(conn, 204, "")

          {:error, reason} ->
            Logger.warning("Invalid notification: \#{inspect(reason)}")
            send_resp(conn, 401, "Invalid notification")
        end
      end
  """
  @spec validate_notification(map(), String.t() | nil) :: :ok | {:error, atom()}
  def validate_notification(notification_payload, expected_client_state) do
    case notification_payload do
      %{"value" => [%{"clientState" => ^expected_client_state} | _]} ->
        :ok

      %{"value" => [%{"clientState" => _} | _]} ->
        {:error, :invalid_client_state}

      %{"value" => [%{} | _]} when is_nil(expected_client_state) ->
        # No client state expected or provided
        :ok

      _ ->
        {:error, :invalid_payload}
    end
  end

  @doc """
  Parses a notification payload into structured format.

  A single webhook POST can contain multiple notifications.

  ## Parameters

  - `payload` - The JSON payload from Microsoft's POST request

  ## Returns

  List of notification maps with standardized keys:
  - `subscription_id` - Which subscription triggered this
  - `client_state` - The validation token
  - `change_type` - "created", "updated", or "deleted"
  - `resource` - Resource path that changed
  - `resource_data` - Details about the changed resource

  ## Examples

      notifications = Subscriptions.parse_notification(webhook_payload)

      Enum.each(notifications, fn notif ->
        case notif.change_type do
          "created" -> handle_created(notif.resource)
          "updated" -> handle_updated(notif.resource)
          "deleted" -> handle_deleted(notif.resource)
        end
      end)
  """
  @spec parse_notification(map()) :: [
          %{
            subscription_id: String.t(),
            client_state: String.t() | nil,
            change_type: String.t(),
            resource: String.t(),
            resource_data: map()
          }
        ]
  def parse_notification(payload) do
    payload
    |> Map.get("value", [])
    |> Enum.map(fn notification ->
      %{
        subscription_id: notification["subscriptionId"],
        client_state: notification["clientState"],
        change_type: notification["changeType"],
        resource: notification["resource"],
        resource_data: notification["resourceData"]
      }
    end)
  end

  # Private helper functions

  defp convert_datetime_fields(subscription) do
    case Map.get(subscription, :expiration_date_time) do
      %DateTime{} = dt ->
        Map.put(subscription, :expiration_date_time, DateTime.to_iso8601(dt))

      _ ->
        subscription
    end
  end

  defp validate_create_params(data) do
    required = ["changeType", "notificationUrl", "resource", "expirationDateTime"]

    missing = Enum.filter(required, fn key -> !Map.has_key?(data, key) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required_fields, missing}}
    end
  end

  defp handle_create_error(%{"error" => %{"message" => message}}) when is_binary(message) do
    cond do
      String.contains?(message, "validation") ->
        {:error,
         {:validation_timeout,
          "Webhook validation failed - ensure endpoint responds within 10 seconds"}}

      String.contains?(message, "https") ->
        {:error, {:invalid_url, "Notification URL must use HTTPS"}}

      true ->
        {:error, {:create_failed, message}}
    end
  end

  defp handle_create_error(body), do: {:error, {:create_failed, body}}

  defp handle_error(401, _), do: {:error, :unauthorized}
  defp handle_error(403, _), do: {:error, :forbidden}
  defp handle_error(404, _), do: {:error, :not_found}

  defp handle_error(status, %{"error" => %{"message" => message}}) do
    {:error, {:graph_api_error, %{status: status, message: message}}}
  end

  defp handle_error(status, body) do
    {:error, {:graph_api_error, %{status: status, body: body}}}
  end
end
