# Msg Library Enhancement Plan

## Context

MatMan (Matter Management system) needs to sync matter events and deadlines with Microsoft Graph Calendar Events and Planner Tasks. MatterEvents can belong to either **Microsoft 365 Groups (shared)** or **Users (personal)**. This document outlines the required enhancements to the Msg library to support this functionality.

**Related Document:** See `docs/matter-events-plan.md` in the MatMan repository for the full implementation plan.

## Authentication Context

**Important:** MatMan operates using **application-only authentication** (app permissions) rather than delegated user permissions. This means:

- All API calls are made in the context of the application, not a specific user
- Endpoints use `/users/{user_id}/...` or `/groups/{group_id}/...` instead of `/me/...`
- Requires `user_id` or `group_id` parameter for most operations
- Uses app permissions like `Calendars.ReadWrite`, `Group.ReadWrite.All`, `Tasks.ReadWrite.All`

## Group vs User Resources

MatMan supports two scopes for MatterEvents:

1. **Group-scoped events**: Shared calendar events/tasks in M365 Groups
   - Endpoints: `/groups/{group_id}/calendar/events`, `/groups/{group_id}/planner/...`
   - Use cases: Court dates, filing deadlines, team meetings
   - Visibility: All group members see these in Outlook, Teams, Planner

2. **User-scoped events**: Personal calendar events/tasks for individual users
   - Endpoints: `/users/{user_id}/events`, `/users/{user_id}/planner/tasks`
   - Use cases: Personal tasks, individual research deadlines
   - Visibility: Only the assigned user sees these

The Msg library needs to support both scopes for calendar and planner operations.

## Required Capabilities

The Msg library needs to provide:

1. M365 Group management (create, get, list, add/remove members)
2. Calendar Event CRUD operations for both Groups and Users with open extension support
3. Open extension management (for tagging Microsoft resources)
4. Planner Plans and Tasks CRUD operations for both Groups and Users
5. Webhook subscription management (for real-time sync)
6. Proper error handling and pagination
7. Etag-based optimistic concurrency control

## New Modules to Implement

### 1. Groups Module

**File:** `lib/msg/groups.ex`

**Purpose:** Manage Microsoft 365 Groups for matter-level shared resources

#### Functions

##### `create/2` - Create a new M365 Group

```elixir
@spec create(Req.Request.t(), map()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `POST /groups`
- **Required fields:**
  - `displayName` - group name
  - `mailEnabled` - boolean (true for groups with email)
  - `mailNickname` - email alias
  - `securityEnabled` - boolean (true for security groups)
  - `groupTypes` - list, include `["Unified"]` for M365 Groups
- **Optional fields:**
  - `description` - group description
  - `visibility` - "Public" or "Private"
  - `owners@odata.bind` - list of user IDs to set as owners
  - `members@odata.bind` - list of user IDs to set as members
- **Returns:** Created group with `id`

**Example:**

```elixir
{:ok, group} = Groups.create(client, %{
  displayName: "Matter: Smith v. Jones",
  mailEnabled: true,
  mailNickname: "matter-smith-jones",
  securityEnabled: false,
  groupTypes: ["Unified"],
  description: "Legal matter workspace",
  visibility: "Private"
})
```

##### `get/2` - Get a group

```elixir
@spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `GET /groups/{id}`
- **Returns:** Group details

##### `list/1` - List all groups

```elixir
@spec list(Req.Request.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
```

- **Endpoint:** `GET /groups`
- **Options:**
  - `:auto_paginate` - boolean, default true
  - `:filter` - OData filter string
- **Returns:** List of groups

##### `add_member/3` - Add member to group

```elixir
@spec add_member(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
```

- **Endpoint:** `POST /groups/{group_id}/members/$ref`
- **Parameters:**
  - `group_id` - group ID
  - `user_id` - user ID to add
- **Returns:** `:ok` on success

##### `remove_member/3` - Remove member from group

```elixir
@spec remove_member(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
```

- **Endpoint:** `DELETE /groups/{group_id}/members/{user_id}/$ref`
- **Returns:** `:ok` on success

##### `add_owner/3` - Add owner to group

```elixir
@spec add_owner(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
```

- **Endpoint:** `POST /groups/{group_id}/owners/$ref`
- **Returns:** `:ok` on success

##### `list_members/2` - List group members

```elixir
@spec list_members(Req.Request.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
```

- **Endpoint:** `GET /groups/{group_id}/members`
- **Returns:** List of user objects

---

### 2. Calendar Events Module

**File:** `lib/msg/calendar/events.ex`

**Purpose:** Interact with Microsoft Graph Calendar Events API for both Groups and Users

#### Functions

##### `list/2` - List calendar events

```elixir
@spec list(Req.Request.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
```

- **Endpoints:**
  - User calendar: `GET /users/{user_id}/events`
  - Group calendar: `GET /groups/{group_id}/calendar/events`
- **Query parameters:**
  - `$filter` - filter events (e.g., by date range)
  - `$select` - select specific fields
  - `$top` - page size
  - `$skip` - pagination offset
  - `$orderby` - sort order
  - `$expand` - expand related entities (e.g., `extensions`)
- **Options (one required):**
  - `:user_id` - user ID or UPN (for personal calendar)
  - `:group_id` - group ID (for group calendar)
  - `:start_datetime` - filter events starting after this date
  - `:end_datetime` - filter events starting before this date
  - `:auto_paginate` - boolean, default true (fetch all pages)
- **Returns:** List of event maps
- **Pagination:** Handle `@odata.nextLink` automatically if `auto_paginate: true`

**Examples:**

```elixir
# List user calendar events
{:ok, events} = Events.list(client,
  user_id: "user@contoso.com",
  start_datetime: ~U[2025-01-01 00:00:00Z],
  end_datetime: ~U[2025-12-31 23:59:59Z]
)

# List group calendar events
{:ok, events} = Events.list(client,
  group_id: "group-id-here",
  start_datetime: ~U[2025-01-01 00:00:00Z]
)
```

##### `get/3` - Get a single event

```elixir
@spec get(Req.Request.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
```

- **Endpoints:**
  - User calendar: `GET /users/{user_id}/events/{event_id}`
  - Group calendar: `GET /groups/{group_id}/calendar/events/{event_id}`
- **Parameters:**
  - `event_id` - ID of the event to retrieve
- **Options (one required):**
  - `:user_id` - user ID or UPN
  - `:group_id` - group ID
  - `:expand_extensions` - boolean, include extensions in response
  - `:select` - list of fields to select
- **Returns:** Event map or error

**Examples:**

```elixir
{:ok, event} = Events.get(client, "AAMkAGI...", user_id: "user@contoso.com", expand_extensions: true)
{:ok, event} = Events.get(client, "AAMkAGI...", group_id: "group-id-here")
```

##### `create/2` - Create a new event

```elixir
@spec create(Req.Request.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
```

- **Endpoints:**
  - User calendar: `POST /users/{user_id}/events`
  - Group calendar: `POST /groups/{group_id}/calendar/events`
- **Required fields in event map:**
  - `subject` - string, event title
  - `start` - map with `dateTime` and `timeZone`
  - `end` - map with `dateTime` and `timeZone`
- **Optional fields:**
  - `body` - map with `contentType` and `content`
  - `location` - map with `displayName`
  - `attendees` - list of attendee maps
  - `isAllDay` - boolean
  - Many more (see MS Graph docs)
- **Options (one required):**
  - `:user_id` - user ID or UPN
  - `:group_id` - group ID
- **Returns:** Created event with generated `id`

**Examples:**

```elixir
event = %{
  subject: "Court Hearing",
  start: %{
    dateTime: "2025-01-15T10:00:00",
    timeZone: "Pacific Standard Time"
  },
  end: %{
    dateTime: "2025-01-15T11:00:00",
    timeZone: "Pacific Standard Time"
  },
  location: %{displayName: "Courtroom 5A"}
}

# Create in user calendar
{:ok, created_event} = Events.create(client, event, user_id: "user@contoso.com")

# Create in group calendar
{:ok, created_event} = Events.create(client, event, group_id: "group-id-here")
```

##### `update/3` - Update an existing event

```elixir
@spec update(Req.Request.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
```

- **Endpoints:**
  - User calendar: `PATCH /users/{user_id}/events/{event_id}`
  - Group calendar: `PATCH /groups/{group_id}/calendar/events/{event_id}`
- **Parameters:**
  - `event_id` - ID of event to update
  - `updates` - map of fields to update
- **Options (one required):**
  - `:user_id` - user ID or UPN
  - `:group_id` - group ID
- **Supports:** Partial updates (only include changed fields)
- **Concurrency:** Optionally include `If-Match` header with etag
- **Returns:** Updated event

**Examples:**

```elixir
{:ok, updated} = Events.update(client, event_id, %{subject: "Updated Title"}, user_id: "user@contoso.com")
{:ok, updated} = Events.update(client, event_id, %{subject: "Updated Title"}, group_id: "group-id-here")
```

##### `delete/2` - Delete an event

```elixir
@spec delete(Req.Request.t(), String.t(), keyword()) :: :ok | {:error, term()}
```

- **Endpoints:**
  - User calendar: `DELETE /users/{user_id}/events/{event_id}`
  - Group calendar: `DELETE /groups/{group_id}/calendar/events/{event_id}`
- **Parameters:**
  - `event_id` - ID of event to delete
- **Options (one required):**
  - `:user_id` - user ID or UPN
  - `:group_id` - group ID
- **Returns:** `:ok` on success (204 status)

**Examples:**

```elixir
:ok = Events.delete(client, event_id, user_id: "user@contoso.com")
:ok = Events.delete(client, event_id, group_id: "group-id-here")
```

##### `create_with_extension/3` - Create event with open extension

```elixir
@spec create_with_extension(Req.Request.t(), map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
```

- **Purpose:** Create event and add extension in optimized way
- **Implementation options:**
  1. Single request if API supports (check docs)
  2. Two requests: create event, then add extension
- **Parameters:**
  - `event` - event data map
  - `extension` - extension data map
- **Options (one required):**
  - `:user_id` - user ID or UPN
  - `:group_id` - group ID
- **Extension map must include:**
  - `extensionName` - unique name (e.g., "com.matman.eventMetadata")
  - Custom properties as needed
- **Returns:** Event with extension included

**Examples:**

```elixir
event = %{subject: "Court Date", start: %{...}, end: %{...}}
extension = %{
  extensionName: "com.matman.eventMetadata",
  matterId: "mat_abc123",
  eventId: "mev_xyz789",
  scope: "user"
}

# Create in user calendar with extension
{:ok, event_with_ext} = Events.create_with_extension(client, event, extension, user_id: "user@contoso.com")

# Create in group calendar with extension
{:ok, event_with_ext} = Events.create_with_extension(client, event, extension, group_id: "group-id-here")
```

##### `get_with_extensions/2` - Get event including extensions

```elixir
@spec get_with_extensions(Req.Request.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
```

- **Endpoints:**
  - User calendar: `GET /users/{user_id}/events/{event_id}?$expand=extensions`
  - Group calendar: `GET /groups/{group_id}/calendar/events/{event_id}?$expand=extensions`
- **Parameters:**
  - `event_id` - ID of event
- **Options (one required):**
  - `:user_id` - user ID or UPN
  - `:group_id` - group ID
- **Returns:** Event map with `extensions` field populated

**Examples:**

```elixir
{:ok, event} = Events.get_with_extensions(client, event_id, user_id: "user@contoso.com")
matman_ext = Enum.find(event["extensions"], fn ext ->
  ext["extensionName"] == "com.matman.eventMetadata"
end)

{:ok, event} = Events.get_with_extensions(client, event_id, group_id: "group-id-here")
```

---

### 3. Open Extensions Module

**File:** `lib/msg/extensions.ex`

**Purpose:** Manage open extensions on Microsoft Graph resources (events, tasks, messages, etc.)

**Background:** Open extensions allow adding custom properties to Microsoft Graph resources. MatMan uses this to tag Calendar Events with matter_id, event_id, and org_id for bidirectional sync.

#### Functions

##### `create/4` - Create an open extension

```elixir
@spec create(Req.Request.t(), String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
```

- **Parameters:**
  - `client` - authenticated Req.Request.t()
  - `resource_path` - path to resource (e.g., "/me/events/AAMkAGI...")
  - `extension_name` - unique name in reverse DNS format
  - `properties` - map of custom properties
- **Endpoint:** `POST /{resource_path}/extensions`
- **Body:** Includes `extensionName` and custom properties
- **Returns:** Created extension

**Example:**

```elixir
Extensions.create(
  client,
  "/users/user@contoso.com/events/AAMkAGI...",
  "com.matman.eventMetadata",
  %{matterId: "mat_123", eventId: "mev_456"}
)
```

##### `list/2` - List all extensions on a resource

```elixir
@spec list(Req.Request.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
```

- **Endpoint:** `GET /{resource_path}/extensions`
- **Returns:** List of extension maps

##### `get/3` - Get a specific extension

```elixir
@spec get(Req.Request.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
```

- **Parameters:**
  - `resource_path` - resource containing extension
  - `extension_name` - name of extension to retrieve
- **Endpoint:** `GET /{resource_path}/extensions/{extension_name}`
- **Returns:** Extension map or 404 error

##### `update/4` - Update extension properties

```elixir
@spec update(Req.Request.t(), String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `PATCH /{resource_path}/extensions/{extension_name}`
- **Supports:** Partial updates
- **Returns:** Updated extension

##### `delete/3` - Delete an extension

```elixir
@spec delete(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
```

- **Endpoint:** `DELETE /{resource_path}/extensions/{extension_name}`
- **Returns:** `:ok` on success

#### Helper Functions

##### `filter_resources_by_extension/5` - Query resources by extension value

```elixir
@spec filter_resources_by_extension(
  Req.Request.t(),
  String.t(),
  String.t(),
  String.t(),
  term(),
  keyword()
) :: {:ok, [map()]} | {:error, term()}
```

- **Parameters:**
  - `resource_type` - e.g., "events"
  - `extension_name` - e.g., "com.matman.eventMetadata"
  - `property_name` - e.g., "matterId"
  - `property_value` - e.g., "mat_123"
- **Options:**
  - `:user_id` - **required** - user ID or UPN
- **Purpose:** Find all resources with specific extension property value
- **Implementation:** Use `$filter` with extension syntax on `/users/{user_id}/{resource_type}`
- **Example filter:** `extensions/any(e: e/id eq 'com.matman.eventMetadata' and e/matterId eq 'mat_123')`
- **Critical for MatMan:** Finding MS events for a given matter

**Example:**

```elixir
{:ok, events} = Extensions.filter_resources_by_extension(
  client,
  "events",
  "com.matman.eventMetadata",
  "matterId",
  "mat_abc123",
  user_id: "user@contoso.com"
)
```

---

### 4. Planner Plans Module

**File:** `lib/msg/planner/plans.ex`

**Purpose:** Manage Planner Plans (containers for tasks)

**Note:** Planner Plans are primarily group-based resources. Each M365 Group can have multiple Plans, but typically MatMan will use one Plan per Matter.

#### Functions

##### `list/2` - List plans

```elixir
@spec list(Req.Request.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
```

- **Endpoints:**
  - `GET /groups/{group_id}/planner/plans` - plans for specific group (primary)
  - `GET /users/{user_id}/planner/plans` - plans accessible by user
- **Options (one required):**
  - `:group_id` - group ID (for group's plans - primary use case)
  - `:user_id` - user ID or UPN (for user's accessible plans)
  - `:auto_paginate` - boolean, default true
- **Returns:** List of plan maps

##### `get/2` - Get a single plan

```elixir
@spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `GET /planner/plans/{id}`
- **Returns:** Plan map with details

##### `create/2` - Create a new plan

```elixir
@spec create(Req.Request.t(), map()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `POST /planner/plans`
- **Required fields:**
  - `owner` - group ID that owns the plan
  - `title` - plan name
- **Returns:** Created plan with generated `id`

**Example:**

```elixir
{:ok, plan} = Plans.create(client, %{
  owner: "group-id-here",
  title: "Matter: Smith v. Jones"
})
```

##### `update/3` - Update a plan

```elixir
@spec update(Req.Request.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `PATCH /planner/plans/{id}`
- **Requires:** `If-Match` header with etag
- **Returns:** Updated plan

##### `delete/3` - Delete a plan

```elixir
@spec delete(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
```

- **Endpoint:** `DELETE /planner/plans/{id}`
- **Parameters:**
  - `plan_id` - ID of plan to delete
  - `etag` - current etag for concurrency control
- **Requires:** `If-Match` header with etag
- **Returns:** `:ok` on success

---

### 5. Planner Tasks Module

**File:** `lib/msg/planner/tasks.ex`

**Purpose:** Manage Planner Tasks within Plans and for Users

**Note:** Tasks can belong to group Plans or be personal tasks. MatMan uses both:

- Group tasks: Shared tasks in Matter's Planner Plan
- User tasks: Personal tasks assigned to individual users

#### Functions

##### `list_by_plan/2` - List tasks in a plan

```elixir
@spec list_by_plan(Req.Request.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
```

- **Endpoint:** `GET /planner/plans/{plan_id}/tasks`
- **Parameters:**
  - `plan_id` - ID of the plan
- **Options:**
  - `:auto_paginate` - boolean, default true
- **Returns:** List of task maps (all tasks in the plan)
- **Use case:** Get all group-level tasks for a Matter

##### `list_by_user/2` - List tasks assigned to user

```elixir
@spec list_by_user(Req.Request.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
```

- **Endpoint:** `GET /users/{user_id}/planner/tasks`
- **Options:**
  - `:user_id` - **required** - user ID or UPN
  - `:auto_paginate` - boolean, default true
- **Returns:** All tasks assigned to specified user (across all plans)
- **Use case:** Get all personal tasks for a user, potentially across multiple matters

##### `get/2` - Get a single task

```elixir
@spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `GET /planner/tasks/{id}`
- **Returns:** Task map with details

##### `create/2` - Create a new task

```elixir
@spec create(Req.Request.t(), map()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `POST /planner/tasks`
- **Required fields:**
  - `planId` - ID of plan to create task in
  - `title` - task title
- **Optional fields:**
  - `dueDateTime` - due date
  - `startDateTime` - start date
  - `percentComplete` - 0-100
  - `assignments` - map of user assignments
  - `description` - task description (HTML)
  - `priority` - 0-10 (5 is default)
- **Returns:** Created task with generated `id` and `etag`

**Example:**

```elixir
{:ok, task} = Tasks.create(client, %{
  planId: "plan-id",
  title: "File motion by Jan 15",
  dueDateTime: "2025-01-15T17:00:00Z",
  description: "<!-- matman:matter_id=mat_123,event_id=mev_456 -->\nFile motion for summary judgment"
})
```

##### `update/3` - Update a task

```elixir
@spec update(Req.Request.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `PATCH /planner/tasks/{id}`
- **Requires:** `If-Match` header with etag
- **Supports:** Partial updates
- **Returns:** Updated task with new etag
- **Error handling:** 412 Precondition Failed if etag mismatch

**Important:** Always use the latest etag. Get task first if etag unknown.

##### `delete/3` - Delete a task

```elixir
@spec delete(Req.Request.t(), String.t(), String.t()) :: :ok | {:error, term()}
```

- **Endpoint:** `DELETE /planner/tasks/{id}`
- **Parameters:**
  - `task_id` - ID of task to delete
  - `etag` - current etag for concurrency control
- **Requires:** `If-Match` header with etag
- **Returns:** `:ok` on success

#### Helper Functions

##### `parse_matman_metadata/1` - Extract MatMan metadata from description

```elixir
@spec parse_matman_metadata(String.t()) :: %{matter_id: String.t(), event_id: String.t()} | nil
```

- **Purpose:** Parse HTML comment metadata from task description
- **Format:** `<!-- matman:matter_id=mat_123,event_id=mev_456,org_id=org_789 -->`
- **Returns:** Map of metadata or nil if not found

##### `embed_matman_metadata/2` - Embed MatMan metadata in description

```elixir
@spec embed_matman_metadata(String.t(), map()) :: String.t()
```

- **Purpose:** Add/update HTML comment in description with MatMan IDs
- **Preserves:** Existing description content
- **Returns:** Updated description string

**Example:**

```elixir
desc = "File the motion\nDue by end of day"
updated_desc = Tasks.embed_matman_metadata(desc, %{
  matter_id: "mat_123",
  event_id: "mev_456",
  org_id: "org_789"
})
# Returns: "<!-- matman:matter_id=mat_123,event_id=mev_456,org_id=org_789 -->\nFile the motion\nDue by end of day"
```

---

### 6. Subscriptions Module

**File:** `lib/msg/subscriptions.ex`

**Purpose:** Manage Microsoft Graph change notification subscriptions (webhooks)

**Background:** Subscriptions enable webhooks for real-time updates when Calendar Events or other resources change. MatMan needs this for bidirectional sync without polling. Supports both group and user calendar subscriptions.

#### Functions

##### `create/2` - Create a subscription

```elixir
@spec create(Req.Request.t(), map()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `POST /subscriptions`
- **Required fields:**
  - `changeType` - comma-separated: "created,updated,deleted"
  - `notificationUrl` - HTTPS endpoint for webhooks
  - `resource` - resource to monitor (e.g., "/users/{user_id}/events")
  - `expirationDateTime` - ISO 8601 datetime
- **Optional fields:**
  - `clientState` - secret string returned in notifications for validation
- **Max subscription duration:**
  - Calendar events: 4230 minutes (≈3 days)
  - Other resources: varies
- **Returns:** Subscription with `id` and actual `expirationDateTime`

**Example:**

```elixir
{:ok, subscription} = Subscriptions.create(client, %{
  changeType: "created,updated,deleted",
  notificationUrl: "https://matman.app/api/webhooks/microsoft/notifications",
  resource: "/users/user@contoso.com/events",
  expirationDateTime: DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second),
  clientState: "secret-validation-token-123"
})
```

**Important:** Microsoft will send a validation GET request to `notificationUrl` with a `validationToken` query parameter. Your endpoint must respond with the validation token as plain text within 10 seconds.

##### `list/1` - List subscriptions

```elixir
@spec list(Req.Request.t()) :: {:ok, [map()]} | {:error, term()}
```

- **Endpoint:** `GET /subscriptions`
- **Returns:** All active subscriptions for this application

##### `get/2` - Get a subscription

```elixir
@spec get(Req.Request.t(), String.t()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `GET /subscriptions/{id}`
- **Returns:** Subscription details

##### `update/3` - Update a subscription (renew)

```elixir
@spec update(Req.Request.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
```

- **Endpoint:** `PATCH /subscriptions/{id}`
- **Primary use:** Renew subscription by updating `expirationDateTime`
- **Returns:** Updated subscription

**Example:**

```elixir
# Renew subscription for another 3 days
{:ok, renewed} = Subscriptions.update(client, subscription_id, %{
  expirationDateTime: DateTime.add(DateTime.utc_now(), 3 * 24 * 60 * 60, :second)
})
```

##### `delete/2` - Delete a subscription

```elixir
@spec delete(Req.Request.t(), String.t()) :: :ok | {:error, term()}
```

- **Endpoint:** `DELETE /subscriptions/{id}`
- **Returns:** `:ok` on success

#### Helper Functions

##### `validate_notification/2` - Validate webhook notification

```elixir
@spec validate_notification(map(), String.t() | nil) :: :ok | {:error, :invalid_client_state}
```

- **Parameters:**
  - `notification_payload` - the JSON payload from Microsoft
  - `expected_client_state` - the clientState you specified when creating subscription
- **Purpose:** Verify notification is authentic
- **Checks:** clientState matches expected value
- **Returns:** `:ok` if valid, error otherwise

**Example:**

```elixir
case Subscriptions.validate_notification(payload, "secret-validation-token-123") do
  :ok ->
    # Process notification
  {:error, :invalid_client_state} ->
    # Reject notification
end
```

---

## General Implementation Guidelines

### Error Handling

All functions should handle common Microsoft Graph errors consistently:

| Status Code | Error | Handling |
|------------|-------|----------|
| 401 | Unauthorized | Token expired/invalid - return `{:error, :unauthorized}` |
| 403 | Forbidden | Insufficient permissions - return `{:error, :forbidden}` |
| 404 | Not Found | Resource doesn't exist - return `{:error, :not_found}` |
| 409 | Conflict | Concurrent update - return `{:error, :conflict}` |
| 412 | Precondition Failed | Etag mismatch - return `{:error, {:etag_mismatch, current_etag}}` |
| 429 | Too Many Requests | Rate limiting - implement exponential backoff retry |
| 500/502/503 | Server Error | Microsoft service error - implement retry with backoff |

**Error Return Format:**

```elixir
# Generic errors
{:error, :unauthorized}
{:error, :forbidden}
{:error, :not_found}
{:error, :rate_limited}

# Errors with additional context
{:error, {:graph_api_error, %{status: 500, message: "Internal server error"}}}
{:error, {:etag_mismatch, "W/\"JzEt...\"}}
{:error, {:invalid_request, "Missing required field: subject"}}
```

### Retry Logic

Implement automatic retries for:

- **429 (Rate Limited):** Respect `Retry-After` header, exponential backoff
- **500/502/503 (Server Errors):** Exponential backoff, max 3 retries

**Do not retry:**

- 400 (Bad Request)
- 401 (Unauthorized)
- 403 (Forbidden)
- 404 (Not Found)
- 409 (Conflict)

### Authentication

- All modules accept `Req.Request.t()` as first parameter (pre-authenticated client)
- No need to handle authentication in these modules
- Assume client created via `Msg.Client.new/1` with proper credentials
- Client should already have authorization token attached

### Required API Scopes

Document in module-level `@moduledoc`. **Note:** These are **application permissions**, not delegated permissions.

| Module | Required Application Permissions |
|--------|--------------------------------|
| Groups | `Group.ReadWrite.All` (application permission) |
| Calendar.Events | `Calendars.ReadWrite` (application permission) |
| Extensions | Same as resource being extended |
| Planner.Plans | `Tasks.ReadWrite.All` or `Group.ReadWrite.All` |
| Planner.Tasks | `Tasks.ReadWrite.All` or `Group.ReadWrite.All` |
| Subscriptions | Same as resource being monitored |

**Important:** The app operates using application-only authentication, accessing resources on behalf of the application itself, not a signed-in user. `Group.ReadWrite.All` is required for creating and managing M365 Groups.

### Pagination Handling

For list operations returning collections:

1. **Check for `@odata.nextLink`** in response
2. **Provide `auto_paginate` option:**
   - `true` (default): Automatically fetch all pages, return complete list
   - `false`: Return first page + next link token
3. **Return format when `auto_paginate: false`:**

```elixir
{:ok, %{
  items: [...],
  next_link: "https://graph.microsoft.com/v1.0/users/user@contoso.com/events?$skip=10"
}}
```

**Example implementation:**

```elixir
def list(client, opts \\ []) do
  user_id = Keyword.fetch!(opts, :user_id)
  auto_paginate = Keyword.get(opts, :auto_paginate, true)

  case fetch_page(client, "/users/#{user_id}/events", []) do
    {:ok, %{items: items, next_link: nil}} ->
      {:ok, items}

    {:ok, %{items: items, next_link: next_link}} when auto_paginate ->
      fetch_all_pages(client, next_link, items)

    {:ok, result} ->
      {:ok, result}
  end
end
```

### Etag Handling (Planner API)

Planner API requires etags for updates and deletes:

1. **Store etag from GET/POST responses**
2. **Include in `If-Match` header for PATCH/DELETE**
3. **Handle 412 Precondition Failed:**
   - Fetch latest version
   - Return error with current etag: `{:error, {:etag_mismatch, current_etag}}`
   - Let caller decide: retry, merge, or abort

**Example:**

```elixir
def update(client, task_id, updates) do
  # Fetch current task to get latest etag
  case get(client, task_id) do
    {:ok, task} ->
      etag = task["@odata.etag"]

      client
      |> Req.patch(url: "/planner/tasks/#{task_id}", json: updates,
           headers: [{"If-Match", etag}])
      |> handle_response()

    error -> error
  end
end
```

### Type Specifications

Use detailed type specs for better documentation and Dialyzer support:

```elixir
@type event :: %{
  required(:subject) => String.t(),
  required(:start) => datetime_value(),
  required(:end) => datetime_value(),
  optional(:body) => body_value(),
  optional(:location) => location_value(),
  # ... other fields
}

@type datetime_value :: %{
  dateTime: String.t(),  # ISO 8601
  timeZone: String.t()   # IANA timezone
}
```

### Logging

Add debug logging for:

- API requests (endpoint, method)
- Pagination (pages fetched)
- Retry attempts
- Errors

**Example:**

```elixir
require Logger

def create(client, event, opts) do
  user_id = Keyword.fetch!(opts, :user_id)
  Logger.debug("Creating calendar event for user #{user_id}: #{event["subject"]}")

  case Req.post(client, url: "/users/#{user_id}/events", json: event) do
    {:ok, response} ->
      Logger.debug("Event created: #{response.body["id"]}")
      {:ok, response.body}

    {:error, error} ->
      Logger.error("Failed to create event: #{inspect(error)}")
      {:error, error}
  end
end
```

---

## Testing Requirements

### Unit Tests

Each module should have comprehensive tests:

1. **Happy path tests:** Successful operations with valid data
2. **Error scenarios:**
   - 401 Unauthorized
   - 403 Forbidden
   - 404 Not Found
   - 429 Rate Limited
   - 500 Server Error
3. **Pagination tests:** Multi-page results
4. **Etag tests:** Successful updates, etag mismatches
5. **Extension tests:** Create, retrieve, filter by extension
6. **Validation tests:** Invalid input handling

### Test Strategy

#### Option 1: Mock HTTP responses

```elixir
# Use Mimic or Mox to mock Req responses
test "creates event successfully" do
  mock_response = %{
    status: 201,
    body: %{"id" => "event-123", "subject" => "Test"}
  }

  expect(Req, :post, fn _client, _opts -> {:ok, mock_response} end)

  assert {:ok, event} = Events.create(client, %{subject: "Test", ...})
  assert event["id"] == "event-123"
end
```

#### Option 2: Use ExVCR for recorded fixtures

```elixir
use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

test "creates event successfully" do
  use_cassette "create_event_success" do
    {:ok, event} = Events.create(client, test_event())
    assert event["subject"] == "Test Event"
  end
end
```

**Option 3: Real sandbox tenant** (ideal but requires setup)

- Use Microsoft 365 Developer Program sandbox
- Real integration tests
- Slower but highest confidence

### Test Coverage Goals

- Minimum 80% line coverage
- 100% coverage for error handling paths
- All public functions have at least one test

---

## Documentation Standards

### Module-level Documentation

Each module should have:

```elixir
defmodule Msg.Calendar.Events do
  @moduledoc """
  Interact with Microsoft Graph Calendar Events API.

  Provides functions to create, read, update, and delete calendar events,
  including support for open extensions to tag events with custom metadata.

  ## Required Application Permissions

  - `Calendars.ReadWrite` - application permission to read/write all users' calendars

  **Note:** This is an application permission, not a delegated permission. The app
  accesses calendars on behalf of itself using app-only authentication.

  ## Examples

      # Create a client (application-only authentication)
      client = Msg.Client.new(%{
        client_id: "...",
        client_secret: "...",
        tenant_id: "..."
      })

      # List events for a user
      {:ok, events} = Events.list(client, user_id: "user@contoso.com")

      # Create an event with extension
      event = %{subject: "Meeting", start: %{...}, end: %{...}}
      extension = %{extensionName: "com.myapp.metadata", customId: "123"}
      {:ok, created} = Events.create_with_extension(client, event, extension, user_id: "user@contoso.com")

  ## References

  - [Microsoft Graph Events API](https://learn.microsoft.com/en-us/graph/api/resources/event)
  - [Open Extensions](https://learn.microsoft.com/en-us/graph/api/resources/opentypeextension)
  """
end
```

### Function-level Documentation

Each public function should have:

```elixir
@doc """
Creates a new calendar event.

## Parameters

- `client` - Authenticated Req.Request client
- `event` - Map with event properties:
  - `:subject` (required) - Event title
  - `:start` (required) - Start datetime map with `dateTime` and `timeZone`
  - `:end` (required) - End datetime map with `dateTime` and `timeZone`
  - `:body` (optional) - Event body/description
  - `:location` (optional) - Location information
  - `:attendees` (optional) - List of attendees

## Returns

- `{:ok, event}` - Created event with generated ID
- `{:error, :unauthorized}` - Invalid or expired token
- `{:error, {:invalid_request, message}}` - Validation error
- `{:error, term}` - Other errors

## Examples

    event = %{
      subject: "Team Meeting",
      start: %{
        dateTime: "2025-01-15T14:00:00",
        timeZone: "Pacific Standard Time"
      },
      end: %{
        dateTime: "2025-01-15T15:00:00",
        timeZone: "Pacific Standard Time"
      }
    }

    {:ok, created} = Events.create(client, event, user_id: "user@contoso.com")

## See Also

- `create_with_extension/3` - Create event with open extension
- `update/3` - Update an existing event
"""
@spec create(Req.Request.t(), map()) :: {:ok, map()} | {:error, term()}
def create(client, event) do
  # implementation
end
```

---

## Implementation Priority

Implement modules in this order for maximum value:

1. **Groups** (1 day)
   - Foundation for group-scoped resources
   - Required before group calendar/planner operations
   - Create, get, list, add/remove members

2. **Calendar.Events** (1.5 days)
   - Core sync functionality for both group and user calendars
   - Most critical for MatMan
   - Supports both `/groups/{id}/calendar/events` and `/users/{id}/events`

3. **Extensions** (1 day)
   - Required for tagging Calendar events
   - Enables bidirectional sync matching
   - Works with both group and user resources

4. **Subscriptions** (1 day)
   - Webhooks for real-time sync
   - Supports both group and user calendar subscriptions
   - Reduces polling, improves UX

5. **Planner.Plans** (0.5 days)
   - Group-based plans for shared tasks
   - Secondary sync target
   - Can be deferred if needed

6. **Planner.Tasks** (0.5 days)
   - Tasks for both group plans and user assignments
   - Includes metadata helpers (HTML comment parsing)
   - Secondary sync target

7. **Testing & Documentation** (1 day)
   - Critical for quality
   - Don't skip!

**Total Estimated Time:** ~6.5 days

---

## Open Questions for Msg Maintainer

Please consider and decide:

1. **Code organization:**
   - Separate files for Calendar, Planner, Extensions?
   - Or group related modules?
   - Current structure: `lib/msg/users.ex` (suggest: `lib/msg/calendar/events.ex`)

2. **Pagination strategy:**
   - Return all results by default (simpler for callers)?
   - Or require explicit pagination handling (more control)?
   - Recommendation: `auto_paginate: true` default with opt-out

3. **Retry logic:**
   - Should Msg handle rate limiting retries automatically?
   - Or let MatMan handle it?
   - Recommendation: Msg handles 429/500s, returns other errors immediately

4. **Type specifications:**
   - Use generic `map()` for flexibility?
   - Or define structs (e.g., `%Event{}`, `%Task{}`)?
   - Recommendation: Start with `map()`, add structs later if valuable

5. **Testing approach:**
   - Mock HTTP responses?
   - Use ExVCR fixtures?
   - Real sandbox tenant?
   - Recommendation: Start with mocks, add ExVCR fixtures for integration tests

6. **Extension filtering:**
   - Is the `$filter` syntax for extension properties correct?
   - Need to test with real API
   - May need adjustment based on API behavior

---

## Success Criteria

The Msg library enhancements are complete when:

- ✅ All 6 required modules implemented (Groups, Calendar, Extensions, Planner x2, Subscriptions)
- ✅ Groups module supports create, get, list, add/remove members
- ✅ Calendar.Events supports both group and user calendars
- ✅ Planner.Tasks supports both group plans and user task lists
- ✅ All functions have proper error handling
- ✅ Pagination works correctly for list operations
- ✅ Etag handling works for Planner updates
- ✅ Extension filtering works to find tagged events
- ✅ Test coverage >80%
- ✅ All public functions documented
- ✅ MatMan can successfully sync events bidirectionally (both group and user scopes)

---

## Migration Guide for Msg Users

If making breaking changes, provide migration guide:

**Before:**

```elixir
# Old approach (doesn't exist yet, so N/A)
```

**After:**

```elixir
# New Calendar Events API
client = Msg.Client.new(credentials)
{:ok, events} = Msg.Calendar.Events.list(client)
```

---

## References

- [Microsoft Graph Calendar API](https://learn.microsoft.com/en-us/graph/api/resources/calendar)
- [Microsoft Graph Events API](https://learn.microsoft.com/en-us/graph/api/resources/event)
- [Open Extensions](https://learn.microsoft.com/en-us/graph/api/resources/opentypeextension)
- [Planner API](https://learn.microsoft.com/en-us/graph/api/resources/planner-overview)
- [Change Notifications (Webhooks)](https://learn.microsoft.com/en-us/graph/api/resources/subscription)
- [Error Handling](https://learn.microsoft.com/en-us/graph/errors)
- [Throttling and Batching](https://learn.microsoft.com/en-us/graph/throttling)
