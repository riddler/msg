defmodule Msg.AuthTestHelpers do
  @moduledoc """
  Authentication helper functions for integration tests.

  Provides utilities for obtaining delegated permission clients using
  Resource Owner Password Credentials (ROPC) flow for automated testing.
  """

  alias Msg.{Auth, Client}

  @doc """
  Gets a delegated client for testing using ROPC flow.

  This function uses the Resource Owner Password Credentials (ROPC) flow
  to obtain an access token with delegated permissions. This is only suitable
  for automated testing and requires:

  - Azure AD work/school account (not personal Microsoft account)
  - MICROSOFT_SYSTEM_USER_EMAIL in environment
  - MICROSOFT_SYSTEM_USER_PASSWORD in environment
  - Test user without MFA enabled
  - "Allow public client flows" enabled in Azure app registration

  ## Parameters

  - `credentials` - Map with `:client_id`, `:client_secret`, `:tenant_id`
  - `opts` - Keyword list:
    - `:scopes` (optional) - List of scopes to request

  ## Returns

  - `Req.Request.t()` - Authenticated client with delegated permissions
  - `nil` - If ROPC credentials are not available in environment

  ## Examples

      # In integration test setup
      credentials = %{
        client_id: System.fetch_env!("MICROSOFT_CLIENT_ID"),
        client_secret: System.fetch_env!("MICROSOFT_CLIENT_SECRET"),
        tenant_id: System.fetch_env!("MICROSOFT_TENANT_ID")
      }

      # Get delegated client (returns nil if credentials not available)
      delegated_client = Msg.AuthTestHelpers.get_delegated_client(credentials)

      if delegated_client do
        # Run tests requiring delegated permissions
        {:ok, events} = Msg.Calendar.Events.list(delegated_client, group_id: group_id)
      else
        # Skip tests requiring delegated permissions
        IO.puts("Skipping delegated permission tests - no ROPC credentials")
      end

  ## Environment Variables Required

  - `MICROSOFT_SYSTEM_USER_EMAIL` - Email of test user (e.g., testuser@tenant.onmicrosoft.com)
  - `MICROSOFT_SYSTEM_USER_PASSWORD` - Password of test user

  ## See Also

  - `Msg.Auth.get_tokens_via_password/2` - The underlying OAuth function
  """
  @spec get_delegated_client(map(), keyword()) :: Req.Request.t() | nil
  def get_delegated_client(credentials, opts \\ []) do
    case System.get_env("MICROSOFT_SYSTEM_USER_EMAIL") do
      nil ->
        nil

      email ->
        password = System.get_env("MICROSOFT_SYSTEM_USER_PASSWORD")

        if !password do
          raise """
          MICROSOFT_SYSTEM_USER_EMAIL is set but MICROSOFT_SYSTEM_USER_PASSWORD is missing.
          Either provide both or remove both to skip delegated permission tests.
          """
        end

        scopes =
          Keyword.get(opts, :scopes, [
            "Calendars.ReadWrite.Shared",
            "Group.ReadWrite.All",
            "offline_access"
          ])

        case Auth.get_tokens_via_password(credentials,
               username: email,
               password: password,
               scopes: scopes
             ) do
          {:ok, tokens} ->
            Client.new(tokens.access_token)

          {:error, %{body: %{"suberror" => "consent_required"}}} ->
            # Admin consent not yet granted - return nil to skip delegated tests
            # This is expected in fresh setups
            nil

          {:error, error} ->
            raise """
            Failed to obtain delegated access token via ROPC flow.
            Error: #{inspect(error)}

            This usually means:
            - Wrong username or password
            - MFA is enabled on test account (ROPC doesn't support MFA)
            - "Allow public client flows" not enabled in app registration
            - Missing API permissions or admin consent (run interactive consent flow first)

            See Msg.Auth.get_tokens_via_password/2 documentation for setup requirements.
            """
        end
    end
  end

  @doc """
  Checks if delegated permission tests can run.

  Returns `true` if ROPC credentials are available in environment,
  `false` otherwise.

  ## Examples

      if Msg.AuthTestHelpers.delegated_tests_available?() do
        test "group calendar operations" do
          # Test code here
        end
      else
        @tag :skip
        test "group calendar operations" do
          # Will be skipped
        end
      end
  """
  @spec delegated_tests_available?() :: boolean()
  def delegated_tests_available? do
    !is_nil(System.get_env("MICROSOFT_SYSTEM_USER_EMAIL")) &&
      !is_nil(System.get_env("MICROSOFT_SYSTEM_USER_PASSWORD"))
  end

  @doc """
  Gets both application-only and delegated clients for testing.

  Convenience function that returns both types of authenticated clients
  for integration tests that need to test both permission types.

  ## Parameters

  - `credentials` - Map with `:client_id`, `:client_secret`, `:tenant_id`

  ## Returns

  Map with:
  - `:app_client` - Client with application-only permissions
  - `:delegated_client` - Client with delegated permissions (or nil if not available)

  ## Examples

      setup_all do
        credentials = %{
          client_id: System.fetch_env!("MICROSOFT_CLIENT_ID"),
          client_secret: System.fetch_env!("MICROSOFT_CLIENT_SECRET"),
          tenant_id: System.fetch_env!("MICROSOFT_TENANT_ID")
        }

        clients = Msg.AuthTestHelpers.get_test_clients(credentials)

        {:ok, clients}
      end

      test "user calendar with app permissions", %{app_client: client} do
        {:ok, events} = Events.list(client, user_id: "user@contoso.com")
      end

      test "group calendar with delegated permissions", %{delegated_client: client} do
        if client do
          {:ok, events} = Events.list(client, group_id: "group-id")
        else
          # Skip test
          assert true
        end
      end
  """
  @spec get_test_clients(map()) :: %{
          app_client: Req.Request.t(),
          delegated_client: Req.Request.t() | nil
        }
  def get_test_clients(credentials) do
    %{
      app_client: Client.new(credentials),
      delegated_client: get_delegated_client(credentials)
    }
  end
end
