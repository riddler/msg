defmodule Msg.Planner.Plans do
  @moduledoc """
  Manage Microsoft Planner Plans.

  Planner Plans are containers for tasks. Each Microsoft 365 Group can have multiple Plans,
  which provide project management functionality within Teams and other Microsoft 365 apps.

  ## Required Permissions

  ### Group Plans

  - **Application:** ❌ Not supported
  - **Delegated:** `Tasks.ReadWrite` or `Group.ReadWrite.All` - **required** for group plans

  ### User-Accessible Plans

  - **Application:** `Tasks.ReadWrite.All` - read/write all plans
  - **Delegated:** `Tasks.ReadWrite` - read/write user's accessible plans

  ## Authentication

  - **Group plans** (`/groups/{group_id}/planner/plans`): **Requires delegated permissions**
  - **User-accessible plans** (`/users/{user_id}/planner/plans`): Works with application-only

  ## Etag-Based Concurrency

  Planner API requires etags for all update and delete operations to prevent conflicts.
  Etags are returned in the `@odata.etag` field and must be included in the `If-Match`
  header for PATCH and DELETE requests.

  ## Examples

      # List plans for a group (requires delegated permissions)
      delegated_client = Msg.Client.new(refresh_token, credentials)
      {:ok, plans} = Msg.Planner.Plans.list(delegated_client, group_id: "group-id")

      # Create a plan
      {:ok, plan} = Msg.Planner.Plans.create(delegated_client, %{
        owner: "group-id",
        title: "Project: Q1 Marketing Campaign"
      })

      # Update a plan (requires etag)
      {:ok, updated} = Msg.Planner.Plans.update(delegated_client, plan_id, %{
        title: "Updated Title"
      }, etag: plan["@odata.etag"])

      # Delete a plan (requires etag)
      :ok = Msg.Planner.Plans.delete(delegated_client, plan_id, plan["@odata.etag"])

  ## References

  - [Planner Plans API](https://learn.microsoft.com/en-us/graph/api/resources/plannerplan)
  - [Etags in Planner](https://learn.microsoft.com/en-us/graph/api/resources/planner-overview#planner-resource-versioning)
  """

  alias Msg.{Pagination, Request}

  @doc """
  Lists Planner Plans.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `opts` - Keyword list of options:
    - `:group_id` - Group ID (for group's plans - primary use case)
    - `:user_id` - User ID or UPN (for user's accessible plans)
    - `:auto_paginate` - Boolean, default true (fetch all pages)

  **Note:** Either `:group_id` or `:user_id` is required.

  ## Returns

  - `{:ok, [plan]}` - List of plans (when auto_paginate: true)
  - `{:ok, %{items: [plan], next_link: url}}` - First page with next link (when auto_paginate: false)
  - `{:error, term}` - Error

  ## Examples

      # List plans for a group
      {:ok, plans} = Msg.Planner.Plans.list(client, group_id: "group-id")

      # List plans accessible by user
      {:ok, plans} = Msg.Planner.Plans.list(client, user_id: "user@contoso.com")
  """
  @spec list(Req.Request.t(), keyword()) :: {:ok, [map()]} | {:ok, map()} | {:error, term()}
  def list(client, opts) do
    auto_paginate = Keyword.get(opts, :auto_paginate, true)
    base_path = build_base_path(opts)

    case Pagination.fetch_page(client, base_path, []) do
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
  Gets a single Planner Plan by ID.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `plan_id` - ID of the plan to retrieve

  ## Returns

  - `{:ok, plan}` - Plan map with details including `@odata.etag`
  - `{:error, :not_found}` - Plan doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, plan} = Msg.Planner.Plans.get(client, "plan-id")
      etag = plan["@odata.etag"]
  """
  @spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get(client, plan_id) do
    case Request.get(client, "/planner/plans/#{plan_id}") do
      {:ok, plan} ->
        {:ok, plan}

      {:error, %{status: status, body: body}} ->
        handle_error(status, body)

      error ->
        error
    end
  end

  @doc """
  Creates a new Planner Plan.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `plan` - Map with plan properties:
    - `:owner` (required) - Group ID that owns the plan
    - `:title` (required) - Plan name

  ## Returns

  - `{:ok, plan}` - Created plan with generated `id` and `@odata.etag`
  - `{:error, :unauthorized}` - Invalid or expired token
  - `{:error, {:invalid_request, message}}` - Validation error
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, plan} = Msg.Planner.Plans.create(client, %{
        owner: "group-id-here",
        title: "Project: Q1 Marketing Campaign"
      })
  """
  @spec create(Req.Request.t(), map()) :: {:ok, map()} | {:error, term()}
  def create(client, plan) do
    plan_converted = Request.convert_keys(plan)

    case Req.post(client, url: "/planner/plans", json: plan_converted) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a Planner Plan.

  **Important:** Requires the current etag for concurrency control. If the etag doesn't
  match the current version, the update will fail with a 412 Precondition Failed error.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `plan_id` - ID of plan to update
  - `updates` - Map of fields to update (typically just `:title`)
  - `opts` - Keyword list of options:
    - `:etag` (required) - Current etag from the plan

  ## Returns

  - `{:ok, plan}` - Updated plan with new `@odata.etag`
  - `{:error, {:etag_mismatch, current_etag}}` - Etag conflict (412)
  - `{:error, :not_found}` - Plan doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      # Get current plan first to obtain etag
      {:ok, plan} = Msg.Planner.Plans.get(client, plan_id)

      {:ok, updated} = Msg.Planner.Plans.update(client, plan_id,
        %{title: "Updated Project Name"},
        etag: plan["@odata.etag"]
      )
  """
  @spec update(Req.Request.t(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def update(client, plan_id, updates, opts) do
    etag = Keyword.fetch!(opts, :etag)
    updates_converted = Request.convert_keys(updates)

    case Req.patch(client,
           url: "/planner/plans/#{plan_id}",
           json: updates_converted,
           headers: [{"If-Match", etag}]
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 412, body: body}} ->
        # Etag mismatch - fetch current version to get new etag
        case get(client, plan_id) do
          {:ok, current_plan} ->
            {:error, {:etag_mismatch, current_plan["@odata.etag"]}}

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
  Deletes a Planner Plan.

  **Important:** Requires the current etag for concurrency control.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `plan_id` - ID of plan to delete
  - `etag` - Current etag for concurrency control

  ## Returns

  - `:ok` - Plan deleted successfully (204 status)
  - `{:error, {:etag_mismatch, current_etag}}` - Etag conflict (412)
  - `{:error, :not_found}` - Plan doesn't exist
  - `{:error, term}` - Other errors

  ## Examples

      {:ok, plan} = Msg.Planner.Plans.get(client, plan_id)
      :ok = Msg.Planner.Plans.delete(client, plan_id, plan["@odata.etag"])
  """
  @spec delete(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete(client, plan_id, etag) do
    case Req.delete(client, url: "/planner/plans/#{plan_id}", headers: [{"If-Match", etag}]) do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: 412, body: body}} ->
        # Etag mismatch - fetch current version to get new etag
        case get(client, plan_id) do
          {:ok, current_plan} ->
            {:error, {:etag_mismatch, current_plan["@odata.etag"]}}

          _ ->
            handle_error(412, body)
        end

      {:ok, %{status: status, body: body}} ->
        handle_error(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp build_base_path(opts) do
    cond do
      group_id = Keyword.get(opts, :group_id) ->
        "/groups/#{group_id}/planner/plans"

      user_id = Keyword.get(opts, :user_id) ->
        "/users/#{user_id}/planner/plans"

      true ->
        raise ArgumentError, "Either :group_id or :user_id must be provided"
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
