defmodule Msg.Planner.TasksTest do
  use ExUnit.Case, async: true

  alias Msg.Planner.Tasks

  describe "list_by_user/2" do
    test "requires user_id in options" do
      client = %Req.Request{}

      assert_raise KeyError, fn ->
        Tasks.list_by_user(client, [])
      end
    end
  end

  describe "update/3" do
    test "requires etag in options" do
      client = %Req.Request{}
      task_id = "task-123"
      updates = %{percent_complete: 50}

      assert_raise KeyError, fn ->
        Tasks.update(client, task_id, updates, [])
      end
    end
  end

  describe "parse_metadata/1" do
    test "returns nil for nil description" do
      assert Tasks.parse_metadata(nil) == nil
    end

    test "returns nil for description without metadata" do
      description = "Just a regular task description"
      assert Tasks.parse_metadata(description) == nil
    end

    test "parses metadata from HTML comment" do
      description = """
      <!-- metadata:project_id=proj_123,resource_id=res_456 -->
      Complete the deliverable
      Due by end of day
      """

      metadata = Tasks.parse_metadata(description)

      assert metadata == %{
               project_id: "proj_123",
               resource_id: "res_456"
             }
    end

    test "parses metadata with multiple fields" do
      description =
        "<!-- metadata:project_id=proj_123,resource_id=res_456,organization_id=org_789 -->\nTask description"

      metadata = Tasks.parse_metadata(description)

      assert metadata == %{
               project_id: "proj_123",
               resource_id: "res_456",
               organization_id: "org_789"
             }
    end

    test "handles metadata with spaces" do
      description = "<!--  metadata: project_id=proj_123 , resource_id=res_456  -->\nDescription"

      metadata = Tasks.parse_metadata(description)

      assert metadata == %{
               project_id: "proj_123",
               resource_id: "res_456"
             }
    end

    test "returns nil if metadata comment not at start" do
      description = """
      Some text first
      <!-- metadata:project_id=proj_123 -->
      More text
      """

      assert Tasks.parse_metadata(description) == nil
    end
  end

  describe "embed_metadata/2" do
    test "embeds metadata in nil description" do
      metadata = %{project_id: "proj_123", resource_id: "res_456"}

      result = Tasks.embed_metadata(nil, metadata)

      assert result =~ ~r/^<!-- metadata:/
      assert result =~ "project_id=proj_123"
      assert result =~ "resource_id=res_456"
    end

    test "embeds metadata in empty description" do
      metadata = %{project_id: "proj_123"}

      result = Tasks.embed_metadata("", metadata)

      assert result == "<!-- metadata:project_id=proj_123 -->"
    end

    test "embeds metadata before existing description" do
      description = "Complete the deliverable\nDue by end of day"
      metadata = %{project_id: "proj_123", resource_id: "res_456"}

      result = Tasks.embed_metadata(description, metadata)

      assert result =~ ~r/^<!-- metadata:/
      assert result =~ "Complete the deliverable"
      assert result =~ "Due by end of day"
    end

    test "replaces existing metadata" do
      description = "<!-- metadata:old_key=old_value -->\nOriginal description"
      metadata = %{new_key: "new_value"}

      result = Tasks.embed_metadata(description, metadata)

      assert result =~ "new_key=new_value"
      refute result =~ "old_key=old_value"
      assert result =~ "Original description"
    end

    test "preserves description content when replacing metadata" do
      description = """
      <!-- metadata:project_id=old_123 -->
      First line
      Second line
      Third line
      """

      metadata = %{project_id: "new_456"}

      result = Tasks.embed_metadata(description, metadata)

      assert result =~ "project_id=new_456"
      assert result =~ "First line"
      assert result =~ "Second line"
      assert result =~ "Third line"
    end
  end

  describe "metadata round-trip" do
    test "parse and embed work together" do
      original_metadata = %{
        project_id: "proj_123",
        resource_id: "res_456",
        organization_id: "org_789"
      }

      description = "Task description content"

      # Embed metadata
      with_metadata = Tasks.embed_metadata(description, original_metadata)

      # Parse it back
      parsed_metadata = Tasks.parse_metadata(with_metadata)

      assert parsed_metadata == original_metadata
    end
  end
end
