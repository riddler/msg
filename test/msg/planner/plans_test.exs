defmodule Msg.Planner.PlansTest do
  use ExUnit.Case, async: true

  alias Msg.Planner.Plans

  describe "list/2" do
    test "requires either group_id or user_id" do
      client = %Req.Request{}

      assert_raise ArgumentError, "Either :group_id or :user_id must be provided", fn ->
        Plans.list(client, [])
      end
    end
  end

  describe "update/3" do
    test "requires etag in options" do
      client = %Req.Request{}
      plan_id = "plan-123"
      updates = %{title: "Updated Title"}

      assert_raise KeyError, fn ->
        Plans.update(client, plan_id, updates, [])
      end
    end
  end
end
