defmodule Msg.Extensions do
  @moduledoc """
  Manage open extensions on Microsoft Graph resources.

  Open extensions allow adding custom properties to Microsoft Graph resources (events, tasks,
  messages, etc.). Applications can use this to tag resources with custom metadata for
  synchronization and tracking.

  ## Background

  Open extensions are schema-less JSON objects attached to Graph resources. Each extension
  must have a unique `extensionName` (typically in reverse DNS format) and can contain
  any custom properties.

  ## Required Permissions

  Permissions depend on the resource type being extended:

  - **Calendar Events:** `Calendars.ReadWrite` (application) or `Calendars.ReadWrite` (delegated)
  - **Messages:** `Mail.ReadWrite` (application) or `Mail.ReadWrite` (delegated)
  - **Tasks:** `Tasks.ReadWrite.All` (application) or `Tasks.ReadWrite` (delegated)

  ## Examples

      # Create extension on a calendar event
      {:ok, ext} = Msg.Extensions.create(
        client,
        "/users/user@contoso.com/events/AAMkAGI...",
        "com.example.metadata",
        %{project_id: "proj_123", resource_id: "res_456"}
      )

      # Get specific extension
      {:ok, ext} = Msg.Extensions.get(
        client,
        "/users/user@contoso.com/events/AAMkAGI...",
        "com.example.metadata"
      )

      # Update extension properties
      {:ok, updated} = Msg.Extensions.update(
        client,
        "/users/user@contoso.com/events/AAMkAGI...",
        "com.example.metadata",
        %{project_id: "proj_456"}
      )

      # Delete extension
      :ok = Msg.Extensions.delete(
        client,
        "/users/user@contoso.com/events/AAMkAGI...",
        "com.example.metadata"
      )

  ## References

  - [Open Extensions](https://learn.microsoft.com/en-us/graph/api/resources/opentypeextension)
  - [Add Open Extension](https://learn.microsoft.com/en-us/graph/api/opentypeextension-post-opentypeextension)
  """

  alias Msg.Request

  @doc """
  Creates an open extension on a Microsoft Graph resource.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `resource_path` - Path to resource (e.g., "/users/user@contoso.com/events/AAMkAGI...")
  - `extension_name` - Unique name in reverse DNS format (e.g., "com.example.metadata")
  - `properties` - Map of custom properties

  ## Returns

  - `{:ok, extension}` - Created extension with all properties
  - `{:error, :unauthorized}` - Invalid or expired token
  - `{:error, {:invalid_request, message}}` - Validation error
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, ext} = Msg.Extensions.create(
        client,
        "/users/user@contoso.com/events/AAMkAGI...",
        "com.example.metadata",
        %{project_id: "proj_123", resource_id: "res_456", priority: "high"}
      )
  """
  @spec create(Req.Request.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def create(client, resource_path, extension_name, properties) do
    # Build extension object with @odata.type and extensionName
    extension =
      properties
      |> Request.convert_keys()
      |> Map.put("extensionName", extension_name)
      |> Map.put("@odata.type", "microsoft.graph.openTypeExtension")

    case Req.post(client, url: "#{resource_path}/extensions", json: extension) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all extensions on a resource.

  **Note:** Not all Microsoft Graph resource types support listing extensions.
  Calendar events, for example, require retrieving extensions by ID.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `resource_path` - Path to resource

  ## Returns

  - `{:ok, [extension]}` - List of extensions
  - `{:error, :method_not_allowed}` - Resource type doesn't support listing
  - `{:error, term}` - Other errors

  ## Examples

      # May not work for all resource types
      {:ok, extensions} = Msg.Extensions.list(
        client,
        "/users/user@contoso.com/messages/AAMkAGI..."
      )
  """
  @spec list(Req.Request.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def list(client, resource_path) do
    case Request.get(client, "#{resource_path}/extensions") do
      {:ok, %{"value" => extensions}} ->
        {:ok, extensions}

      {:ok, extension} when is_map(extension) ->
        # Single extension returned instead of collection
        {:ok, [extension]}

      {:error, %{status: 405, body: _}} ->
        {:error, :method_not_allowed}

      {:error, %{status: status, body: body}} ->
        handle_error(status, body)

      error ->
        error
    end
  end

  @doc """
  Gets a specific extension by ID.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `resource_path` - Path to resource
  - `extension_name` - Name/ID of the extension to retrieve

  ## Returns

  - `{:ok, extension}` - Extension map with all properties
  - `{:error, :not_found}` - Extension doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, ext} = Msg.Extensions.get(
        client,
        "/users/user@contoso.com/events/AAMkAGI...",
        "com.example.metadata"
      )

      project_id = ext["projectId"]
  """
  @spec get(Req.Request.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get(client, resource_path, extension_name) do
    case Request.get(client, "#{resource_path}/extensions/#{extension_name}") do
      {:ok, extension} ->
        {:ok, extension}

      {:error, %{status: status, body: body}} ->
        handle_error(status, body)

      error ->
        error
    end
  end

  @doc """
  Updates an extension's properties.

  **Warning:** Microsoft Graph does not support PATCH updates on open extensions for
  all resource types. This function is provided for completeness, but may not work
  for calendar events and other resources. To "update" an extension, you typically
  need to delete and recreate it.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `resource_path` - Path to resource
  - `extension_name` - Name/ID of the extension
  - `updates` - Map of properties to update

  ## Returns

  - `{:ok, extension}` - Updated extension (if supported by resource type)
  - `{:error, :not_found}` - Extension doesn't exist
  - `{:error, {:graph_api_error, _}}` - Update not supported for this resource type
  - `{:error, term}` - Other errors

  ## Examples

      # This may not work for calendar events
      {:ok, updated} = Msg.Extensions.update(
        client,
        "/users/user@contoso.com/messages/AAMkAGI...",
        "com.example.metadata",
        %{priority: "urgent"}
      )
  """
  @spec update(Req.Request.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def update(client, resource_path, extension_name, updates) do
    updates_converted = Request.convert_keys(updates)

    case Req.patch(client,
           url: "#{resource_path}/extensions/#{extension_name}",
           json: updates_converted
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes an extension from a resource.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `resource_path` - Path to resource
  - `extension_name` - Name/ID of the extension to delete

  ## Returns

  - `:ok` - Extension deleted successfully (204 status)
  - `{:error, :not_found}` - Extension doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      :ok = Msg.Extensions.delete(
        client,
        "/users/user@contoso.com/events/AAMkAGI...",
        "com.example.metadata"
      )
  """
  @spec delete(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete(client, resource_path, extension_name) do
    case Req.delete(client, url: "#{resource_path}/extensions/#{extension_name}") do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Note: filter_resources_by_extension is not implemented in this module
  # because it's resource-type specific. For calendar events, this would be
  # implemented in the Msg.Calendar.Events module using OData filters.
  # Example: $filter=extensions/any(e: e/id eq 'com.example.metadata' and e/projectId eq 'proj_123')

  # Private functions

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
