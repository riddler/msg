defmodule Msg.Planner.Tasks do
  @moduledoc """
  Manage Microsoft Planner Tasks.

  Planner Tasks belong to Plans and can be assigned to users. Tasks support custom metadata
  embedded in the description field via HTML comments for application-specific data.

  ## Required Permissions

  ### Tasks in Group Plans

  - **Application:** ❌ Not supported
  - **Delegated:** `Tasks.ReadWrite` or `Group.ReadWrite.All` - **required** for group plan tasks

  ### User Tasks

  - **Application:** `Tasks.ReadWrite.All` - read/write all tasks
  - **Delegated:** `Tasks.ReadWrite` - read/write user's tasks

  ## Authentication

  - **Tasks in group plans:** **Requires delegated permissions** (refresh token)
  - **User tasks:** Works with application-only authentication

  ## Etag-Based Concurrency

  Like Plans, Tasks require etags for all update and delete operations. Etags are returned
  in the `@odata.etag` field and must be included in the `If-Match` header.

  ## Metadata Embedding

  Since Planner tasks don't support open extensions, this module provides helper functions
  to embed custom metadata in task descriptions using HTML comments:

      <!-- metadata:project_id=proj_123,resource_id=res_456 -->

  ## Examples

      # List tasks in a plan
      {:ok, tasks} = Msg.Planner.Tasks.list_by_plan(client, "plan-id")

      # List tasks assigned to a user
      {:ok, tasks} = Msg.Planner.Tasks.list_by_user(client, user_id: "user@contoso.com")

      # Create task with embedded metadata
      description = Msg.Planner.Tasks.embed_metadata(
        "Complete project deliverable",
        %{project_id: "proj_123", resource_id: "res_456"}
      )

      {:ok, task} = Msg.Planner.Tasks.create(client, %{
        plan_id: "plan-id",
        title: "Complete deliverable by Jan 15",
        description: description
      })

      # Parse metadata from task
      metadata = Msg.Planner.Tasks.parse_metadata(task["description"])
      # => %{project_id: "proj_123", resource_id: "res_456"}

  ## References

  - [Planner Tasks API](https://learn.microsoft.com/en-us/graph/api/resources/plannertask)
  - [Etags in Planner](https://learn.microsoft.com/en-us/graph/api/resources/planner-overview#planner-resource-versioning)
  """

  alias Msg.{Pagination, Request}

  @doc """
  Lists tasks in a Planner Plan.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `plan_id` - ID of the plan
  - `opts` - Keyword list of options:
    - `:auto_paginate` - Boolean, default true (fetch all pages)

  ## Returns

  - `{:ok, [task]}` - List of tasks (all tasks in the plan)
  - `{:error, term}` - Error

  ## Examples

      {:ok, tasks} = Msg.Planner.Tasks.list_by_plan(client, "plan-id")
  """
  @spec list_by_plan(Req.Request.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:ok, map()} | {:error, term()}
  def list_by_plan(client, plan_id, opts \\ []) do
    path = "/planner/plans/#{plan_id}/tasks"
    fetch_tasks_list(client, path, opts)
  end

  @doc """
  Lists tasks assigned to a user.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `opts` - Keyword list of options:
    - `:user_id` (required) - User ID or UPN
    - `:auto_paginate` - Boolean, default true (fetch all pages)

  ## Returns

  - `{:ok, [task]}` - All tasks assigned to specified user (across all plans)
  - `{:error, term}` - Error

  ## Examples

      {:ok, tasks} = Msg.Planner.Tasks.list_by_user(client, user_id: "user@contoso.com")
  """
  @spec list_by_user(Req.Request.t(), keyword()) ::
          {:ok, [map()]} | {:ok, map()} | {:error, term()}
  def list_by_user(client, opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    path = "/users/#{user_id}/planner/tasks"
    fetch_tasks_list(client, path, opts)
  end

  @doc """
  Gets a single Planner Task.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `task_id` - ID of the task to retrieve

  ## Returns

  - `{:ok, task}` - Task map with details including `@odata.etag`
  - `{:error, :not_found}` - Task doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, task} = Msg.Planner.Tasks.get(client, "task-id")
      etag = task["@odata.etag"]
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get(client, task_id) do
    case Request.get(client, "/planner/tasks/#{task_id}") do
      {:ok, task} ->
        {:ok, task}

      {:error, %{status: status, body: body}} ->
        handle_error(status, body)

      error ->
        error
    end
  end

  @doc """
  Creates a new Planner Task.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `task` - Map with task properties:
    - `:plan_id` (required) - ID of plan to create task in
    - `:title` (required) - Task title
    - `:due_date_time` (optional) - Due date
    - `:start_date_time` (optional) - Start date
    - `:percent_complete` (optional) - 0-100
    - `:assignments` (optional) - Map of user assignments
    - `:description` (optional) - Task description

  ## Returns

  - `{:ok, task}` - Created task with generated `id` and `@odata.etag`
  - `{:error, term}` - Error

  ## Examples

      {:ok, task} = Msg.Planner.Tasks.create(client, %{
        plan_id: "plan-id",
        title: "Complete deliverable by Jan 15",
        due_date_time: "2025-01-15T17:00:00Z",
        description: "Complete project deliverable and submit for review"
      })
  """
  @spec create(Req.Request.t(), map()) :: {:ok, map()} | {:error, term()}
  def create(client, task) do
    task_converted = Request.convert_keys(task)

    case Req.post(client, url: "/planner/tasks", json: task_converted) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a Planner Task.

  **Important:** Requires the current etag for concurrency control.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `task_id` - ID of task to update
  - `updates` - Map of fields to update
  - `opts` - Keyword list of options:
    - `:etag` (required) - Current etag from the task

  ## Returns

  - `{:ok, task}` - Updated task with new `@odata.etag`
  - `{:error, {:etag_mismatch, current_etag}}` - Etag conflict (412)
  - `{:error, :not_found}` - Task doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, task} = Msg.Planner.Tasks.get(client, task_id)

      {:ok, updated} = Msg.Planner.Tasks.update(client, task_id,
        %{percent_complete: 50},
        etag: task["@odata.etag"]
      )
  """
  @spec update(Req.Request.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def update(client, task_id, updates, opts) do
    etag = Keyword.fetch!(opts, :etag)
    updates_converted = Request.convert_keys(updates)

    case Req.patch(client,
           url: "/planner/tasks/#{task_id}",
           json: updates_converted,
           headers: [{"If-Match", etag}]
         ) do
      {:ok, %{status: 204}} ->
        # Planner API returns 204 No Content for updates
        # Fetch the updated task to return it
        get(client, task_id)

      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 412, body: body}} ->
        # Etag mismatch - fetch current version to get new etag
        case get(client, task_id) do
          {:ok, current_task} ->
            {:error, {:etag_mismatch, current_task["@odata.etag"]}}

          _ ->
            handle_error(412, body)
        end

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a Planner Task.

  **Important:** Requires the current etag for concurrency control.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `task_id` - ID of task to delete
  - `etag` - Current etag for concurrency control

  ## Returns

  - `:ok` - Task deleted successfully (204 status)
  - `{:error, {:etag_mismatch, current_etag}}` - Etag conflict (412)
  - `{:error, :not_found}` - Task doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, task} = Msg.Planner.Tasks.get(client, task_id)
      :ok = Msg.Planner.Tasks.delete(client, task_id, task["@odata.etag"])
  """
  @spec delete(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete(client, task_id, etag) do
    case Req.delete(client, url: "/planner/tasks/#{task_id}", headers: [{"If-Match", etag}]) do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: 412, body: body}} ->
        # Etag mismatch - fetch current version to get new etag
        case get(client, task_id) do
          {:ok, current_task} ->
            {:error, {:etag_mismatch, current_task["@odata.etag"]}}

          _ ->
            handle_error(412, body)
        end

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parses metadata from a task description.

  Extracts custom metadata embedded in an HTML comment at the beginning of the description.

  ## Parameters

  - `description` - Task description string (may be nil)

  ## Returns

  - Map of metadata key-value pairs, or `nil` if no metadata found

  ## Format

  The metadata must be in the first line as an HTML comment:

      <!-- metadata:key1=value1,key2=value2,key3=value3 -->

  ## Examples

      description = \"\"\"
      <!-- metadata:project_id=proj_123,resource_id=res_456,organization_id=org_789 -->
      Complete the deliverable
      Due by end of day
      \"\"\"

      metadata = Msg.Planner.Tasks.parse_metadata(description)
      # => %{project_id: "proj_123", resource_id: "res_456", organization_id: "org_789"}

      # No metadata
      Msg.Planner.Tasks.parse_metadata("Just a description")
      # => nil
  """
  @spec parse_metadata(String.t() | nil) :: map() | nil
  def parse_metadata(nil), do: nil

  def parse_metadata(description) when is_binary(description) do
    # Match HTML comment at start: <!-- metadata:key1=val1,key2=val2 -->
    case Regex.run(~r/^<!--\s*metadata:([^>]+)\s*-->/, description) do
      [_, metadata_string] ->
        metadata_string
        |> String.split(",")
        |> Enum.reduce(%{}, &parse_metadata_pair/2)

      _ ->
        nil
    end
  end

  defp parse_metadata_pair(pair, acc) do
    case String.split(pair, "=", parts: 2) do
      [key, value] ->
        key_atom = key |> String.trim() |> String.to_atom()
        Map.put(acc, key_atom, String.trim(value))

      _ ->
        acc
    end
  end

  @doc """
  Embeds metadata in a task description.

  Adds or updates an HTML comment at the beginning of the description with custom metadata.
  If metadata already exists, it will be replaced.

  ## Parameters

  - `description` - Existing description (may be nil or empty)
  - `metadata` - Map of metadata key-value pairs

  ## Returns

  - Updated description string with metadata embedded

  ## Examples

      desc = Msg.Planner.Tasks.embed_metadata(
        "Complete the deliverable",
        %{project_id: "proj_123", resource_id: "res_456"}
      )
      # => "<!-- metadata:project_id=proj_123,resource_id=res_456 -->\\nComplete the deliverable"

      # Update existing metadata
      existing = "<!-- metadata:old=value -->\\nOld description"
      updated = Msg.Planner.Tasks.embed_metadata(existing, %{new: "data"})
      # => "<!-- metadata:new=data -->\\nOld description"
  """
  @spec embed_metadata(String.t() | nil, map()) :: String.t()
  def embed_metadata(description, metadata) when is_map(metadata) do
    # Convert metadata map to string
    metadata_string = Enum.map_join(metadata, ",", fn {key, value} -> "#{key}=#{value}" end)

    # Remove existing metadata comment if present
    clean_description =
      case description do
        nil ->
          ""

        desc ->
          String.replace(desc, ~r/^<!--\s*metadata:[^>]+\s*-->\n?/, "")
      end

    # Add new metadata comment
    comment = "<!-- metadata:#{metadata_string} -->"

    if clean_description == "" do
      comment
    else
      comment <> "\n" <> clean_description
    end
  end

  # Private functions

  defp fetch_tasks_list(client, path, opts) do
    auto_paginate = Keyword.get(opts, :auto_paginate, true)

    case Pagination.fetch_page(client, path, []) do
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

  defp handle_error(401, _), do: {:error, :unauthorized}
  defp handle_error(403, _), do: {:error, :forbidden}
  defp handle_error(404, _), do: {:error, :not_found}
  defp handle_error(409, _), do: {:error, :conflict}
  defp handle_error(412, _), do: {:error, :precondition_failed}

  defp handle_error(status, %{"error" => %{"message" => message}}) do
    {:error, {:graph_api_error, %{status: status, message: message}}}
  end

  defp handle_error(status, body) do
    {:error, {:graph_api_error, %{status: status, body: body}}}
  end
end
