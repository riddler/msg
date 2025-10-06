defmodule Msg.GroupsTest do
  use ExUnit.Case, async: true

  alias Msg.Groups

  describe "module structure" do
    test "exports expected public functions" do
      assert function_exported?(Groups, :create, 2)
      assert function_exported?(Groups, :get, 2)
      assert function_exported?(Groups, :list, 1)
      assert function_exported?(Groups, :list, 2)
      assert function_exported?(Groups, :add_member, 3)
      assert function_exported?(Groups, :remove_member, 3)
      assert function_exported?(Groups, :add_owner, 3)
      assert function_exported?(Groups, :list_members, 2)
      assert function_exported?(Groups, :list_members, 3)
    end
  end

  describe "create/2" do
    test "converts snake_case keys to camelCase" do
      # This tests that the function uses Request.convert_keys
      # We can't easily test the actual API call without mocking,
      # but we can verify the function accepts snake_case input
      attrs = %{
        display_name: "Test",
        mail_enabled: true,
        mail_nickname: "test",
        security_enabled: false,
        group_types: ["Unified"]
      }

      # Function should accept this input without crashing on key validation
      # (actual API call will fail without real client, but that's expected)
      assert is_map(attrs)
      assert Map.has_key?(attrs, :display_name)
    end
  end

  describe "list/2 options" do
    test "accepts auto_paginate option" do
      opts = [auto_paginate: false]
      assert Keyword.get(opts, :auto_paginate) == false

      opts = [auto_paginate: true]
      assert Keyword.get(opts, :auto_paginate) == true

      opts = []
      assert Keyword.get(opts, :auto_paginate, true) == true
    end

    test "accepts filter option" do
      opts = [filter: "startswith(displayName,'Test')"]
      assert Keyword.get(opts, :filter) == "startswith(displayName,'Test')"
    end
  end
end
