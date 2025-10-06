defmodule Msg.RequestTest do
  use ExUnit.Case, async: true

  alias Msg.Request

  describe "convert_keys/1" do
    test "converts simple snake_case atom keys to camelCase strings" do
      input = %{display_name: "Test", mail_enabled: true}
      expected = %{"displayName" => "Test", "mailEnabled" => true}

      assert Request.convert_keys(input) == expected
    end

    test "converts nested maps" do
      input = %{
        display_name: "Test",
        start_time: %{
          date_time: "2025-01-15T10:00:00",
          time_zone: "Pacific Standard Time"
        }
      }

      expected = %{
        "displayName" => "Test",
        "startTime" => %{
          "dateTime" => "2025-01-15T10:00:00",
          "timeZone" => "Pacific Standard Time"
        }
      }

      assert Request.convert_keys(input) == expected
    end

    test "converts lists of maps" do
      input = %{
        items: [
          %{display_name: "Item 1", is_active: true},
          %{display_name: "Item 2", is_active: false}
        ]
      }

      expected = %{
        "items" => [
          %{"displayName" => "Item 1", "isActive" => true},
          %{"displayName" => "Item 2", "isActive" => false}
        ]
      }

      assert Request.convert_keys(input) == expected
    end

    test "handles _odata_ pattern in keys" do
      input = %{
        display_name: "Test",
        owners_odata_bind: ["user-1", "user-2"],
        members_odata_bind: ["user-3"]
      }

      expected = %{
        "displayName" => "Test",
        "owners@odata.bind" => ["user-1", "user-2"],
        "members@odata.bind" => ["user-3"]
      }

      assert Request.convert_keys(input) == expected
    end

    test "preserves non-map values" do
      input = %{
        name: "Test",
        count: 42,
        active: true,
        tags: ["tag1", "tag2"],
        metadata: nil
      }

      expected = %{
        "name" => "Test",
        "count" => 42,
        "active" => true,
        "tags" => ["tag1", "tag2"],
        "metadata" => nil
      }

      assert Request.convert_keys(input) == expected
    end

    test "handles string keys (converts them too)" do
      input = %{
        "display_name" => "Test",
        "mail_enabled" => true
      }

      expected = %{
        "displayName" => "Test",
        "mailEnabled" => true
      }

      assert Request.convert_keys(input) == expected
    end

    test "handles complex multi-word snake_case" do
      input = %{
        very_long_field_name: "test",
        another_complex_field_name: "value"
      }

      expected = %{
        "veryLongFieldName" => "test",
        "anotherComplexFieldName" => "value"
      }

      assert Request.convert_keys(input) == expected
    end

    test "handles empty map" do
      assert Request.convert_keys(%{}) == %{}
    end

    test "doesn't double-convert @odata. prefixes" do
      # If a key already has @odata. it should be preserved
      input = %{owners_odata_bind: ["user-1"]}
      result = Request.convert_keys(input)

      assert result == %{"owners@odata.bind" => ["user-1"]}
    end
  end
end
