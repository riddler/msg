defmodule Msg.Integration.AuthTest do
  use ExUnit.Case, async: false

  alias Msg.{Auth, Client, Users}

  @moduletag :integration

  setup do
    credentials = %{
      client_id: System.get_env("MICROSOFT_CLIENT_ID"),
      client_secret: System.get_env("MICROSOFT_CLIENT_SECRET"),
      tenant_id: System.get_env("MICROSOFT_TENANT_ID")
    }

    {:ok, credentials: credentials}
  end

  describe "get_authorization_url/2" do
    test "generates valid authorization URL", %{credentials: credentials} do
      url =
        Auth.get_authorization_url(
          %{client_id: credentials.client_id, tenant_id: credentials.tenant_id},
          redirect_uri: "https://localhost:4000/auth/callback",
          scopes: ["Calendars.ReadWrite.Shared", "Group.ReadWrite.All", "offline_access"],
          state: "test-state-123"
        )

      assert String.starts_with?(
               url,
               "https://login.microsoftonline.com/#{credentials.tenant_id}/oauth2/v2.0/authorize"
             )

      assert url =~ "client_id=#{credentials.client_id}"
      assert url =~ "redirect_uri=https%3A%2F%2Flocalhost%3A4000%2Fauth%2Fcallback"

      assert url =~
               "scope=Calendars.ReadWrite.Shared+Group.ReadWrite.All+offline_access"

      assert url =~ "state=test-state-123"
      assert url =~ "response_type=code"
      assert url =~ "response_mode=query"
    end

    test "generates URL without state parameter", %{credentials: credentials} do
      url =
        Auth.get_authorization_url(
          %{client_id: credentials.client_id, tenant_id: credentials.tenant_id},
          redirect_uri: "https://localhost:4000/auth/callback",
          scopes: ["Calendars.ReadWrite.Shared", "offline_access"]
        )

      refute url =~ "state="
    end

    test "properly encodes redirect URI with special characters", %{credentials: credentials} do
      url =
        Auth.get_authorization_url(
          %{client_id: credentials.client_id, tenant_id: credentials.tenant_id},
          redirect_uri: "https://example.com/auth/callback?org_id=123&test=true",
          scopes: ["offline_access"]
        )

      assert url =~
               "redirect_uri=https%3A%2F%2Fexample.com%2Fauth%2Fcallback%3Forg_id%3D123%26test%3Dtrue"
    end
  end

  describe "exchange_code_for_tokens/3" do
    @tag :skip
    test "exchanges authorization code for tokens", %{credentials: credentials} do
      # This test requires manual OAuth flow to obtain an authorization code
      # To run this test:
      # 1. Run the "generates valid authorization URL" test above
      # 2. Visit the generated URL in a browser
      # 3. Sign in and approve permissions
      # 4. Copy the 'code' parameter from the redirect URL
      # 5. Paste it below and remove @tag :skip

      code = "PASTE_AUTHORIZATION_CODE_HERE"

      {:ok, tokens} =
        Auth.exchange_code_for_tokens(
          code,
          credentials,
          redirect_uri: "https://localhost:4000/auth/callback"
        )

      assert is_binary(tokens.access_token)
      assert is_binary(tokens.refresh_token)
      assert tokens.token_type == "Bearer"
      assert is_integer(tokens.expires_in)
      assert tokens.expires_in > 0
      assert is_binary(tokens.scope)
    end

    test "returns error for invalid authorization code", %{credentials: credentials} do
      result =
        Auth.exchange_code_for_tokens(
          "invalid-code-12345",
          credentials,
          redirect_uri: "https://localhost:4000/auth/callback"
        )

      assert {:error, %OAuth2.Response{}} = result
    end

    test "returns error for mismatched redirect URI", %{credentials: credentials} do
      # Even with an invalid code, this should fail with redirect_uri_mismatch
      # if the redirect URI doesn't match what's registered
      result =
        Auth.exchange_code_for_tokens(
          "invalid-code",
          credentials,
          redirect_uri: "https://wrong-domain.com/callback"
        )

      assert {:error, _} = result
    end
  end

  describe "refresh_access_token/3" do
    @tag :skip
    test "refreshes access token using refresh token", %{credentials: credentials} do
      # This test requires a valid refresh token
      # To run this test:
      # 1. Complete the "exchange_code_for_tokens" test above
      # 2. Copy the refresh_token from the response
      # 3. Paste it below and remove @tag :skip
      # 4. Note: Refresh tokens expire after ~90 days of inactivity

      refresh_token = "PASTE_REFRESH_TOKEN_HERE"

      {:ok, new_tokens} = Auth.refresh_access_token(refresh_token, credentials)

      assert is_binary(new_tokens.access_token)
      assert new_tokens.token_type == "Bearer"
      assert is_integer(new_tokens.expires_in)
      assert new_tokens.expires_in > 0

      # Microsoft may return a new refresh token (token rotation)
      # Always update stored refresh token if present
      if Map.has_key?(new_tokens, :refresh_token) and new_tokens.refresh_token != nil do
        assert is_binary(new_tokens.refresh_token)
      end
    end

    @tag :skip
    test "uses refreshed token to make Graph API call", %{credentials: credentials} do
      # This test verifies the full flow: refresh token -> access token -> API call
      refresh_token = "PASTE_REFRESH_TOKEN_HERE"

      {:ok, tokens} = Auth.refresh_access_token(refresh_token, credentials)

      # Create client with refreshed access token
      client = Client.new(tokens.access_token)

      # Make a simple Graph API call to verify token works
      {:ok, users} = Users.list(client)

      assert is_list(users)
    end

    test "returns error for invalid refresh token", %{credentials: credentials} do
      result = Auth.refresh_access_token("invalid-refresh-token", credentials)

      assert {:error, %{status: status, body: body}} = result
      assert status == 400
      assert body["error"] == "invalid_grant"
    end

    test "returns error for expired refresh token", %{credentials: credentials} do
      # Use a token that's definitely expired (very old format)
      expired_token = "0.ARoA6WgJCMOUoEuZk13qLp0sq9azhoY88OdHjY9MoC4aqj8-AB4.EXPIRED"

      result = Auth.refresh_access_token(expired_token, credentials)

      assert {:error, _} = result
    end

    @tag :skip
    test "optional scopes parameter works", %{credentials: credentials} do
      refresh_token = "PASTE_REFRESH_TOKEN_HERE"

      {:ok, tokens} =
        Auth.refresh_access_token(refresh_token, credentials,
          scopes: ["Calendars.ReadWrite", "offline_access"]
        )

      assert is_binary(tokens.access_token)
      assert String.contains?(tokens.scope, "Calendars.ReadWrite")
    end
  end

  describe "get_app_token/1" do
    test "returns access token with metadata", %{credentials: credentials} do
      {:ok, token_info} = Auth.get_app_token(credentials)

      assert is_binary(token_info.access_token)
      assert token_info.token_type == "Bearer"
      assert is_integer(token_info.expires_in)
      assert token_info.expires_in > 0
    end

    test "returns error for invalid credentials" do
      invalid_creds = %{
        client_id: "invalid-id",
        client_secret: "invalid-secret",
        tenant_id: "invalid-tenant"
      }

      assert {:error, %{status: status}} = Auth.get_app_token(invalid_creds)
      assert status == 400
    end
  end
end
