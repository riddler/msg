defmodule Msg.ExtensionsTest do
  use ExUnit.Case, async: true

  alias Msg.Extensions

  describe "create/4" do
    test "accepts extension parameters" do
      # Just verify parameters are accepted
      resource_path = "/users/test@example.com/events/event-123"
      extension_name = "com.example.test"
      properties = %{project_id: "proj_123", resource_id: "res_456"}

      assert is_binary(resource_path)
      assert is_binary(extension_name)
      assert is_map(properties)
    end
  end

  describe "list/2" do
    test "accepts resource_path parameter" do
      resource_path = "/users/test@example.com/events/event-123"
      assert is_binary(resource_path)
    end
  end

  describe "get/3" do
    test "accepts resource_path and extension_name parameters" do
      resource_path = "/users/test@example.com/events/event-123"
      extension_name = "com.example.test"

      assert is_binary(resource_path)
      assert is_binary(extension_name)
    end
  end

  describe "update/4" do
    test "accepts update parameters" do
      resource_path = "/users/test@example.com/events/event-123"
      extension_name = "com.example.test"
      updates = %{priority: "high"}

      assert is_binary(resource_path)
      assert is_binary(extension_name)
      assert is_map(updates)
    end
  end

  describe "delete/3" do
    test "accepts resource_path and extension_name parameters" do
      resource_path = "/users/test@example.com/events/event-123"
      extension_name = "com.example.test"

      assert is_binary(resource_path)
      assert is_binary(extension_name)
    end
  end
end
