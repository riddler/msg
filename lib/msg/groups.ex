defmodule Msg.Groups do
  @moduledoc """
  Provides functions for interacting with Microsoft 365 Groups via the Graph API.

  This module supports creating, reading, updating, and managing Microsoft 365 Groups
  (also known as Unified Groups), which provide shared workspaces with email, calendar,
  files, and other collaborative features.

  ## Required Application Permissions

  - `Group.ReadWrite.All` - application permission to read and write all groups

  **Note:** This is an application permission, not a delegated permission. The app
  accesses groups on behalf of itself using app-only authentication.

  ## Examples

      # Create a client (application-only authentication)
      client = Msg.Client.new(%{
        client_id: "...",
        client_secret: "...",
        tenant_id: "..."
      })

      # Create a new M365 Group
      {:ok, group} = Msg.Groups.create(client, %{
        display_name: "Matter: Smith v. Jones",
        mail_enabled: true,
        mail_nickname: "matter-smith-jones",
        security_enabled: false,
        group_types: ["Unified"],
        description: "Legal matter workspace",
        visibility: "Private"
      })

      # List all groups
      {:ok, groups} = Msg.Groups.list(client)

      # Get a specific group
      {:ok, group} = Msg.Groups.get(client, group_id)

      # Add a member to the group
      :ok = Msg.Groups.add_member(client, group_id, user_id)

  ## References

  - [Microsoft Graph Groups API](https://learn.microsoft.com/en-us/graph/api/resources/group)
  - [Create Group](https://learn.microsoft.com/en-us/graph/api/group-post-groups)
  """

  alias Msg.Request

  @doc """
  Creates a new Microsoft 365 Group.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `attrs` - Map with group properties:
    - `:display_name` (required) - Group name
    - `:mail_enabled` (required) - Boolean (true for groups with email)
    - `:mail_nickname` (required) - Email alias
    - `:security_enabled` (required) - Boolean (true for security groups)
    - `:group_types` (required) - List, include `["Unified"]` for M365 Groups
    - `:description` (optional) - Group description
    - `:visibility` (optional) - "Public" or "Private"
    - `:owners_odata_bind` (optional) - List of user IDs to set as owners
    - `:members_odata_bind` (optional) - List of user IDs to set as members

  ## Returns

  - `{:ok, group}` - Created group with generated ID
  - `{:error, :unauthorized}` - Invalid or expired token
  - `{:error, {:invalid_request, message}}` - Validation error
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, group} = Msg.Groups.create(client, %{
        display_name: "Project Team",
        mail_enabled: true,
        mail_nickname: "project-team",
        security_enabled: false,
        group_types: ["Unified"],
        description: "Team workspace",
        visibility: "Private"
      })

  ## See Also

  - [Create Group API](https://learn.microsoft.com/en-us/graph/api/group-post-groups)
  """
  @spec create(Req.Request.t(), map()) :: {:ok, map()} | {:error, term()}
  def create(client, attrs) do
    attrs_converted = Request.convert_keys(attrs)

    case Req.post(client, url: "/groups", json: attrs_converted) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a specific group by ID.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `group_id` - ID of the group to retrieve

  ## Returns

  - `{:ok, group}` - Group details
  - `{:error, :not_found}` - Group doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, group} = Msg.Groups.get(client, "group-id-here")
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get(client, group_id) do
    case Request.get(client, "/groups/#{group_id}") do
      {:ok, group} ->
        {:ok, group}

      {:error, %{status: status, body: body}} ->
        handle_error(status, body)

      error ->
        error
    end
  end

  @doc """
  Lists all groups in the organization.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `opts` - Keyword list of options:
    - `:auto_paginate` - Boolean, default true (fetch all pages)
    - `:filter` - OData filter string

  ## Returns

  - `{:ok, [group]}` - List of groups (when auto_paginate: true)
  - `{:ok, %{items: [group], next_link: url}}` - First page with next link (when auto_paginate: false)
  - `{:error, term}` - Error

  ## Examples

      # Get all groups
      {:ok, groups} = Msg.Groups.list(client)

      # Get first page only
      {:ok, %{items: groups, next_link: next}} = Msg.Groups.list(client, auto_paginate: false)

      # Filter groups
      {:ok, groups} = Msg.Groups.list(client, filter: "startswith(displayName,'Matter:')")
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, [map()]} | {:ok, map()} | {:error, term()}
  def list(client, opts \\ []) do
    auto_paginate = Keyword.get(opts, :auto_paginate, true)
    filter = Keyword.get(opts, :filter)

    query_params =
      if filter do
        [{"$filter", filter}]
      else
        []
      end

    case fetch_page(client, "/groups", query_params) do
      {:ok, %{items: items, next_link: next_link}} when auto_paginate and not is_nil(next_link) ->
        fetch_all_pages(client, next_link, items)

      {:ok, %{items: items, next_link: nil}} when auto_paginate ->
        {:ok, items}

      {:ok, result} ->
        {:ok, result}

      error ->
        error
    end
  end

  @doc """
  Adds a member to a group.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `group_id` - ID of the group
  - `user_id` - ID of the user to add as member

  ## Returns

  - `:ok` - Member added successfully
  - `{:error, term}` - Error

  ## Examples

      :ok = Msg.Groups.add_member(client, group_id, user_id)
  """
  @spec add_member(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def add_member(client, group_id, user_id) do
    body = %{
      "@odata.id" => "https://graph.microsoft.com/v1.0/directoryObjects/#{user_id}"
    }

    case Req.post(client, url: "/groups/#{group_id}/members/$ref", json: body) do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Removes a member from a group.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `group_id` - ID of the group
  - `user_id` - ID of the user to remove

  ## Returns

  - `:ok` - Member removed successfully
  - `{:error, term}` - Error

  ## Examples

      :ok = Msg.Groups.remove_member(client, group_id, user_id)
  """
  @spec remove_member(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def remove_member(client, group_id, user_id) do
    case Req.delete(client, url: "/groups/#{group_id}/members/#{user_id}/$ref") do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds an owner to a group.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `group_id` - ID of the group
  - `user_id` - ID of the user to add as owner

  ## Returns

  - `:ok` - Owner added successfully
  - `{:error, term}` - Error

  ## Examples

      :ok = Msg.Groups.add_owner(client, group_id, user_id)
  """
  @spec add_owner(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def add_owner(client, group_id, user_id) do
    body = %{
      "@odata.id" => "https://graph.microsoft.com/v1.0/users/#{user_id}"
    }

    case Req.post(client, url: "/groups/#{group_id}/owners/$ref", json: body) do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all members of a group.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `group_id` - ID of the group
  - `opts` - Keyword list of options:
    - `:auto_paginate` - Boolean, default true (fetch all pages)

  ## Returns

  - `{:ok, [user]}` - List of user objects
  - `{:error, term}` - Error

  ## Examples

      {:ok, members} = Msg.Groups.list_members(client, group_id)
  """
  @spec list_members(Req.Request.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:ok, map()} | {:error, term()}
  def list_members(client, group_id, opts \\ []) do
    auto_paginate = Keyword.get(opts, :auto_paginate, true)

    case fetch_page(client, "/groups/#{group_id}/members", []) do
      {:ok, %{items: items, next_link: next_link}} when auto_paginate and not is_nil(next_link) ->
        fetch_all_pages(client, next_link, items)

      {:ok, %{items: items, next_link: nil}} when auto_paginate ->
        {:ok, items}

      {:ok, result} ->
        {:ok, result}

      error ->
        error
    end
  end

  # Private functions

  defp fetch_page(client, path, query_params) do
    url = if query_params == [], do: path, else: path <> "?" <> URI.encode_query(query_params)

    case Request.get(client, url) do
      {:ok, %{"value" => items} = response} ->
        next_link = Map.get(response, "@odata.nextLink")
        {:ok, %{items: items, next_link: next_link}}

      error ->
        error
    end
  end

  defp fetch_all_pages(client, next_link, acc) when is_binary(next_link) do
    # Extract the path from the full URL
    uri = URI.parse(next_link)
    path = uri.path <> if uri.query, do: "?" <> uri.query, else: ""

    case Request.get(client, path) do
      {:ok, %{"value" => items} = response} ->
        new_acc = acc ++ items

        case Map.get(response, "@odata.nextLink") do
          nil ->
            {:ok, new_acc}

          new_next_link ->
            fetch_all_pages(client, new_next_link, new_acc)
        end

      error ->
        error
    end
  end

  defp fetch_all_pages(_client, nil, acc), do: {:ok, acc}

  defp handle_error(401, _body), do: {:error, :unauthorized}
  defp handle_error(403, _body), do: {:error, :forbidden}
  defp handle_error(404, _body), do: {:error, :not_found}
  defp handle_error(409, _body), do: {:error, :conflict}

  defp handle_error(status, %{"error" => %{"message" => message}}) do
    {:error, {:graph_api_error, %{status: status, message: message}}}
  end

  defp handle_error(status, body) do
    {:error, {:graph_api_error, %{status: status, body: body}}}
  end
end
