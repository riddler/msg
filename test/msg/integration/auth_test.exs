defmodule Msg.Integration.AuthTest do
  use ExUnit.Case, async: false

  alias Msg.{Auth, AuthTestHelpers}

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

  describe "get_tokens_via_password/2" do
    test "returns access token with delegated permissions", %{credentials: credentials} do
      email = System.get_env("MICROSOFT_SYSTEM_USER_EMAIL")
      password = System.get_env("MICROSOFT_SYSTEM_USER_PASSWORD")

      if email && password do
        result =
          Auth.get_tokens_via_password(credentials,
            username: email,
            password: password,
            scopes: ["Calendars.ReadWrite.Shared", "Group.ReadWrite.All", "offline_access"]
          )

        case result do
          {:ok, tokens} ->
            assert is_binary(tokens.access_token)
            assert tokens.token_type == "Bearer"
            assert is_integer(tokens.expires_in)
            assert tokens.expires_in > 0
            assert is_binary(tokens.scope)

            # Refresh token may or may not be present depending on scopes
            if tokens.refresh_token do
              assert is_binary(tokens.refresh_token)
            end

          {:error, %{body: %{"error" => "invalid_grant", "suberror" => "consent_required"}}} ->
            # Skip test if admin consent not yet granted
            # This is expected in fresh setups
            assert true

          {:error, error} ->
            flunk("Unexpected error: #{inspect(error)}")
        end
      else
        # Skip test if ROPC credentials not available
        assert true
      end
    end

    test "returns error for invalid username or password", %{credentials: credentials} do
      result =
        Auth.get_tokens_via_password(credentials,
          username: "invalid@example.com",
          password: "wrong-password"
        )

      assert {:error, %{status: status, body: body}} = result
      assert status == 400
      assert body["error"] == "invalid_grant"
    end

    test "works with test helper", %{credentials: credentials} do
      # Test helper returns nil if credentials not available or consent not granted
      delegated_client = AuthTestHelpers.get_delegated_client(credentials)

      if delegated_client do
        # Verify we got a valid client
        assert %Req.Request{} = delegated_client
        assert delegated_client.options.base_url == "https://graph.microsoft.com/v1.0"

        # Verify it has authorization header (in Req, headers are at top level, not in options)
        assert Map.has_key?(delegated_client.headers, "authorization")
      else
        # Skip if no ROPC credentials or consent not granted
        assert true
      end
    end
  end
end
