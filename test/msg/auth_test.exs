defmodule Msg.AuthTest do
  use ExUnit.Case, async: true

  alias Msg.Auth

  describe "get_authorization_url/2" do
    test "generates URL with all required parameters" do
      url =
        Auth.get_authorization_url(
          %{client_id: "test-client", tenant_id: "test-tenant"},
          redirect_uri: "https://example.com/callback",
          scopes: ["Calendars.ReadWrite", "offline_access"]
        )

      assert String.starts_with?(
               url,
               "https://login.microsoftonline.com/test-tenant/oauth2/v2.0/authorize"
             )

      assert url =~ "client_id=test-client"
      assert url =~ "redirect_uri=https%3A%2F%2Fexample.com%2Fcallback"
      assert url =~ "scope=Calendars.ReadWrite+offline_access"
      assert url =~ "response_type=code"
      assert url =~ "response_mode=query"
    end

    test "includes state parameter when provided" do
      url =
        Auth.get_authorization_url(
          %{client_id: "test-client", tenant_id: "test-tenant"},
          redirect_uri: "https://example.com/callback",
          scopes: ["offline_access"],
          state: "csrf-token-123"
        )

      assert url =~ "state=csrf-token-123"
    end

    test "omits state parameter when not provided" do
      url =
        Auth.get_authorization_url(
          %{client_id: "test-client", tenant_id: "test-tenant"},
          redirect_uri: "https://example.com/callback",
          scopes: ["offline_access"]
        )

      refute url =~ "state="
    end

    test "properly encodes redirect URI" do
      url =
        Auth.get_authorization_url(
          %{client_id: "test-client", tenant_id: "test-tenant"},
          redirect_uri: "https://example.com/auth?foo=bar&baz=qux",
          scopes: ["offline_access"]
        )

      assert url =~ "redirect_uri=https%3A%2F%2Fexample.com%2Fauth%3Ffoo%3Dbar%26baz%3Dqux"
    end

    test "properly encodes scopes with spaces" do
      url =
        Auth.get_authorization_url(
          %{client_id: "test-client", tenant_id: "test-tenant"},
          redirect_uri: "https://example.com/callback",
          scopes: ["Calendars.ReadWrite.Shared", "Group.ReadWrite.All", "offline_access"]
        )

      assert url =~
               "scope=Calendars.ReadWrite.Shared+Group.ReadWrite.All+offline_access"
    end
  end

  describe "get_tokens_via_password/2" do
    test "requires username in opts" do
      credentials = %{
        client_id: "test-client",
        client_secret: "test-secret",
        tenant_id: "test-tenant"
      }

      assert_raise KeyError, fn ->
        Auth.get_tokens_via_password(credentials, password: "test-password")
      end
    end

    test "requires password in opts" do
      credentials = %{
        client_id: "test-client",
        client_secret: "test-secret",
        tenant_id: "test-tenant"
      }

      assert_raise KeyError, fn ->
        Auth.get_tokens_via_password(credentials, username: "test@example.com")
      end
    end
  end
end
