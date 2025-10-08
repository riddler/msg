defmodule Msg.Calendar.Events do
  @moduledoc """
  Interact with Microsoft Graph Calendar Events API.

  Provides functions to create, read, update, and delete calendar events for both
  user calendars (personal) and group calendars (shared). Supports open extensions
  for tagging events with custom metadata.

  ## Required Permissions

  ### User Calendars

  - **Application:** `Calendars.ReadWrite` - read/write all users' calendars
  - **Delegated:** `Calendars.ReadWrite` - read/write user's calendars

  ### Group Calendars

  - **Application:** ❌ Not supported
  - **Delegated:** `Calendars.ReadWrite.Shared` - **required** for group calendar access

  ## Authentication

  - **User calendars** (`/users/{user_id}/events`): Works with application-only authentication
  - **Group calendars** (`/groups/{group_id}/calendar/events`): **Requires delegated permissions**

  ## Examples

      # User calendar with application-only authentication
      app_client = Msg.Client.new(%{
        client_id: "...",
        client_secret: "...",
        tenant_id: "..."
      })
      {:ok, events} = Msg.Calendar.Events.list(app_client, user_id: "user@contoso.com")

      # Group calendar with delegated permissions (refresh token)
      delegated_client = Msg.Client.new(refresh_token, credentials)
      {:ok, events} = Msg.Calendar.Events.list(delegated_client, group_id: "group-id")

      # Create event with extension
      event = %{subject: "Team Meeting", start: %{...}, end: %{...}}
      extension = %{extension_name: "com.example.metadata", project_id: "123"}
      {:ok, created} = Msg.Calendar.Events.create_with_extension(
        app_client, event, extension, user_id: "user@contoso.com"
      )

  ## References

  - [Microsoft Graph Events API](https://learn.microsoft.com/en-us/graph/api/resources/event)
  - [Open Extensions](https://learn.microsoft.com/en-us/graph/api/resources/opentypeextension)
  """

  alias Msg.{Pagination, Request}

  @doc """
  Lists calendar events.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `opts` - Keyword list of options:
    - `:user_id` - User ID or UPN (for personal calendar)
    - `:group_id` - Group ID (for group calendar)
    - `:start_datetime` - Filter events starting after this DateTime
    - `:end_datetime` - Filter events starting before this DateTime
    - `:auto_paginate` - Boolean, default true (fetch all pages)
    - `:filter` - OData filter string
    - `:select` - List of fields to select
    - `:orderby` - OData orderby string

  **Note:** Either `:user_id` or `:group_id` is required.

  ## Returns

  - `{:ok, [event]}` - List of events (when auto_paginate: true)
  - `{:ok, %{items: [event], next_link: url}}` - First page with next link (when auto_paginate: false)
  - `{:error, term}` - Error

  ## Examples

      # List user calendar events
      {:ok, events} = Msg.Calendar.Events.list(client,
        user_id: "user@contoso.com",
        start_datetime: ~U[2025-01-01 00:00:00Z],
        end_datetime: ~U[2025-12-31 23:59:59Z]
      )

      # List group calendar events
      {:ok, events} = Msg.Calendar.Events.list(client,
        group_id: "group-id-here",
        auto_paginate: true
      )
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, [map()]} | {:ok, map()} | {:error, term()}
  def list(client, opts) do
    auto_paginate = Keyword.get(opts, :auto_paginate, true)
    base_path = build_base_path(opts)

    query_params = build_query_params(opts)

    case Pagination.fetch_page(client, base_path, query_params) do
      {:ok, %{items: items, next_link: next_link}} when auto_paginate and not is_nil(next_link) ->
        Pagination.fetch_all_pages(client, next_link, items)

      {:ok, %{items: items, next_link: nil}} when auto_paginate ->
        {:ok, items}

      {:ok, result} ->
        {:ok, result}

      error ->
        error
    end
  end

  @doc """
  Gets a single calendar event.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `event_id` - ID of the event to retrieve
  - `opts` - Keyword list of options:
    - `:user_id` - User ID or UPN (for personal calendar)
    - `:group_id` - Group ID (for group calendar)
    - `:expand_extensions` - Boolean, include extensions in response
    - `:select` - List of fields to select

  **Note:** Either `:user_id` or `:group_id` is required.

  ## Returns

  - `{:ok, event}` - Event map
  - `{:error, :not_found}` - Event doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, event} = Msg.Calendar.Events.get(client, "event-id",
        user_id: "user@contoso.com",
        expand_extensions: true
      )

      {:ok, event} = Msg.Calendar.Events.get(client, "event-id",
        group_id: "group-id-here"
      )
  """
  @spec get(Req.Request.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get(client, event_id, opts) do
    base_path = build_base_path(opts)
    path = "#{base_path}/#{event_id}"

    query_params = []

    query_params =
      if Keyword.get(opts, :expand_extensions) do
        # Expand extensions - Microsoft Graph will return all extensions for the event
        query_params ++ [{"$expand", "extensions"}]
      else
        query_params
      end

    query_params =
      case Keyword.get(opts, :select) do
        nil -> query_params
        fields when is_list(fields) -> query_params ++ [{"$select", Enum.join(fields, ",")}]
      end

    url = if query_params == [], do: path, else: path <> "?" <> URI.encode_query(query_params)

    case Request.get(client, url) do
      {:ok, event} ->
        {:ok, event}

      {:error, %{status: status, body: body}} ->
        handle_error(status, body)

      error ->
        error
    end
  end

  @doc """
  Creates a new calendar event.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `event` - Map with event properties:
    - `:subject` (required) - Event title
    - `:start` (required) - Start datetime map with `date_time` and `time_zone`
    - `:end` (required) - End datetime map with `date_time` and `time_zone`
    - `:body` (optional) - Event body/description
    - `:location` (optional) - Location information
    - `:attendees` (optional) - List of attendees
    - `:is_all_day` (optional) - Boolean
  - `opts` - Keyword list of options:
    - `:user_id` - User ID or UPN (for personal calendar)
    - `:group_id` - Group ID (for group calendar)

  **Note:** Either `:user_id` or `:group_id` is required.

  ## Returns

  - `{:ok, event}` - Created event with generated ID
  - `{:error, :unauthorized}` - Invalid or expired token
  - `{:error, {:invalid_request, message}}` - Validation error
  - `{:error, term}` - Other errors

  ## Examples

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

      {:ok, created} = Msg.Calendar.Events.create(client, event,
        user_id: "user@contoso.com"
      )
  """
  @spec create(Req.Request.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def create(client, event, opts) do
    base_path = build_base_path(opts)
    event_converted = Request.convert_keys(event)

    case Req.post(client, url: base_path, json: event_converted) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates an existing calendar event.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `event_id` - ID of event to update
  - `updates` - Map of fields to update
  - `opts` - Keyword list of options:
    - `:user_id` - User ID or UPN (for personal calendar)
    - `:group_id` - Group ID (for group calendar)

  **Note:** Either `:user_id` or `:group_id` is required.

  ## Returns

  - `{:ok, event}` - Updated event
  - `{:error, :not_found}` - Event doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, updated} = Msg.Calendar.Events.update(client, event_id,
        %{subject: "Updated Title"},
        user_id: "user@contoso.com"
      )
  """
  @spec update(Req.Request.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def update(client, event_id, updates, opts) do
    base_path = build_base_path(opts)
    path = "#{base_path}/#{event_id}"
    updates_converted = Request.convert_keys(updates)

    case Req.patch(client, url: path, json: updates_converted) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a calendar event.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `event_id` - ID of event to delete
  - `opts` - Keyword list of options:
    - `:user_id` - User ID or UPN (for personal calendar)
    - `:group_id` - Group ID (for group calendar)

  **Note:** Either `:user_id` or `:group_id` is required.

  ## Returns

  - `:ok` - Event deleted successfully (204 status)
  - `{:error, :not_found}` - Event doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      :ok = Msg.Calendar.Events.delete(client, event_id, user_id: "user@contoso.com")
      :ok = Msg.Calendar.Events.delete(client, event_id, group_id: "group-id-here")
  """
  @spec delete(Req.Request.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete(client, event_id, opts) do
    base_path = build_base_path(opts)
    path = "#{base_path}/#{event_id}"

    case Req.delete(client, url: path) do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a calendar event with an open extension in a single optimized operation.

  This function creates the event first, then immediately adds the extension.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `event` - Event data map (see `create/3`)
  - `extension` - Extension data map:
    - `:extension_name` (required) - Unique name (e.g., "com.example.metadata")
    - Custom properties as needed
  - `opts` - Keyword list of options:
    - `:user_id` - User ID or UPN (for personal calendar)
    - `:group_id` - Group ID (for group calendar)

  **Note:** Either `:user_id` or `:group_id` is required.

  ## Returns

  - `{:ok, event}` - Created event with extension
  - `{:error, term}` - Error

  ## Examples

      event = %{subject: "Project Milestone", start: %{...}, end: %{...}}
      extension = %{
        extension_name: "com.example.metadata",
        project_id: "proj_abc123",
        resource_id: "res_xyz789"
      }

      {:ok, event_with_ext} = Msg.Calendar.Events.create_with_extension(
        client, event, extension, user_id: "user@contoso.com"
      )
  """
  @spec create_with_extension(Req.Request.t(), map(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_with_extension(client, event, extension, opts) do
    with {:ok, created_event} <- create(client, event, opts) do
      event_id = created_event["id"]
      base_path = build_base_path(opts)
      resource_path = "#{base_path}/#{event_id}"

      # Convert keys and add required @odata.type field for open extensions
      extension_converted =
        extension
        |> Request.convert_keys()
        |> Map.put("@odata.type", "microsoft.graph.openTypeExtension")

      case Req.post(client, url: "#{resource_path}/extensions", json: extension_converted) do
        {:ok, %{status: status, body: ext_body}} when status in 200..299 ->
          # Return the event with the created extension attached
          {:ok, Map.put(created_event, "extensions", [ext_body])}

        {:ok, %{status: status, body: body}} ->
          handle_error(status, body)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Gets a calendar event with a specific extension.

  **Note:** Microsoft Graph does not support listing all extensions on calendar events.
  To retrieve an extension, you must know its ID. Use this function to get an event
  along with a specific extension by providing the extension ID.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `event_id` - ID of the event
  - `extension_id` - ID of the extension to retrieve (e.g., "com.example.metadata")
  - `opts` - Keyword list of options:
    - `:user_id` - User ID or UPN (for personal calendar)
    - `:group_id` - Group ID (for group calendar)

  **Note:** Either `:user_id` or `:group_id` is required.

  ## Returns

  - `{:ok, event}` - Event map with `extensions` field populated with the requested extension
  - `{:error, :not_found}` - Event or extension doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, event} = Msg.Calendar.Events.get_with_extensions(client, event_id,
        "com.example.metadata",
        user_id: "user@contoso.com"
      )

      ext = List.first(event["extensions"])
      project_id = ext["projectId"]
  """
  @spec get_with_extensions(Req.Request.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_with_extensions(client, event_id, extension_id, opts) do
    base_path = build_base_path(opts)
    resource_path = "#{base_path}/#{event_id}"

    # Get event and specific extension
    with {:ok, event} <- get(client, event_id, opts),
         {:ok, extension} <- Request.get(client, "#{resource_path}/extensions/#{extension_id}") do
      {:ok, Map.put(event, "extensions", [extension])}
    end
  end

  # Private functions

  defp build_base_path(opts) do
    cond do
      user_id = Keyword.get(opts, :user_id) ->
        "/users/#{user_id}/events"

      group_id = Keyword.get(opts, :group_id) ->
        "/groups/#{group_id}/calendar/events"

      true ->
        raise ArgumentError, "Either :user_id or :group_id must be provided"
    end
  end

  defp build_query_params(opts) do
    []
    |> add_filter_param(opts)
    |> add_date_range_filter(opts)
    |> add_select_param(opts)
    |> add_orderby_param(opts)
  end

  defp add_filter_param(params, opts) do
    case Keyword.get(opts, :filter) do
      nil -> params
      filter -> params ++ [{"$filter", filter}]
    end
  end

  defp add_date_range_filter(params, opts) do
    start_dt = Keyword.get(opts, :start_datetime)
    end_dt = Keyword.get(opts, :end_datetime)

    case {start_dt, end_dt} do
      {nil, nil} ->
        params

      {%DateTime{} = start_dt, nil} ->
        params ++ [{"$filter", "start/dateTime ge '#{DateTime.to_iso8601(start_dt)}'"}]

      {nil, %DateTime{} = end_dt} ->
        params ++ [{"$filter", "start/dateTime lt '#{DateTime.to_iso8601(end_dt)}'"}]

      {%DateTime{} = start_dt, %DateTime{} = end_dt} ->
        filter =
          "start/dateTime ge '#{DateTime.to_iso8601(start_dt)}' and start/dateTime lt '#{DateTime.to_iso8601(end_dt)}'"

        params ++ [{"$filter", filter}]
    end
  end

  defp add_select_param(params, opts) do
    case Keyword.get(opts, :select) do
      nil -> params
      fields when is_list(fields) -> params ++ [{"$select", Enum.join(fields, ",")}]
    end
  end

  defp add_orderby_param(params, opts) do
    case Keyword.get(opts, :orderby) do
      nil -> params
      orderby -> params ++ [{"$orderby", orderby}]
    end
  end

  defp handle_error(401, _), do: {:error, :unauthorized}
  defp handle_error(403, _), do: {:error, :forbidden}
  defp handle_error(404, _), do: {:error, :not_found}
  defp handle_error(409, _), do: {:error, :conflict}

  defp handle_error(status, %{"error" => %{"message" => message}}) do
    {:error, {:graph_api_error, %{status: status, message: message}}}
  end

  defp handle_error(status, body) do
    {:error, {:graph_api_error, %{status: status, body: body}}}
  end
end
