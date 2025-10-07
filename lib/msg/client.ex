defmodule Msg.Client do
  @moduledoc """
  Responsible for handling authentication and request setup for
  interacting with the Microsoft Graph API.

  Supports three authentication strategies:

  ## 1. Client Credentials (Application-Only)

  Use for application-level permissions (`User.ReadWrite.All`, `Group.ReadWrite.All`, etc.):

      credentials = %{
        client_id: "app-id",
        client_secret: "secret",
        tenant_id: "tenant-id"
      }

      client = Msg.Client.new(credentials)
      {:ok, users} = Msg.Users.list(client)

  **Best for:** User management, group management, user calendars

  ## 2. Pre-existing Access Token

  Use when token lifecycle is managed externally (e.g., by a GenServer):

      access_token = TokenManager.get_token(org_id: 123)
      client = Msg.Client.new(access_token)

  **Best for:** Production apps with token management GenServer

  ## 3. Refresh Token (Delegated Permissions)

  Use for delegated permissions (`Calendars.ReadWrite.Shared`, etc.):

      client = Msg.Client.new(refresh_token, credentials)

  **Best for:** One-off operations, testing, admin tools

  See `Msg.Auth` for obtaining refresh tokens via OAuth authorization code flow.

  ## Required Permissions

  Different resources require different permission types:

  | Resource | Application Permission | Delegated Permission |
  |----------|----------------------|---------------------|
  | User calendars | `Calendars.ReadWrite` | `Calendars.ReadWrite` |
  | Group calendars | ❌ Not supported | `Calendars.ReadWrite.Shared` |
  | User management | `User.ReadWrite.All` | N/A |
  | Group management | `Group.ReadWrite.All` | N/A |

  ## References
  - [Microsoft Graph REST API](https://learn.microsoft.com/en-us/graph/api/overview)
  - [OAuth2 client credentials](https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-client-creds-grant-flow)
  - [OAuth2 authorization code flow](https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow)
  """

  alias Msg.Auth
  alias OAuth2.Client, as: OAuth2Client
  alias OAuth2.Strategy.ClientCredentials
  alias Req.Request

  @type credentials :: %{
          required(:client_id) => String.t(),
          required(:client_secret) => String.t(),
          required(:tenant_id) => String.t()
        }

  @type token_provider :: (credentials() -> String.t())

  @doc """
  Creates an authenticated HTTP client for Microsoft Graph API.

  Supports multiple authentication patterns via overloaded function signatures.

  ## 1-arity: Client Credentials or Access Token

  ### With credentials map:

      credentials = %{
        client_id: "app-id",
        client_secret: "secret",
        tenant_id: "tenant-id"
      }
      client = Msg.Client.new(credentials)

  Exchanges credentials for access token via client credentials flow.

  ### With access token string:

      access_token = "eyJ0eXAi..."
      client = Msg.Client.new(access_token)

  Creates client with pre-existing access token (no token refresh).

  ## 2-arity: Token Provider or Refresh Token

  ### Custom token provider (for testing):

      token_provider = fn _creds -> "stub-token" end
      client = Msg.Client.new(credentials, token_provider)

  ### Refresh token with credentials:

      client = Msg.Client.new(refresh_token, %{
        client_id: "app-id",
        client_secret: "secret",
        tenant_id: "tenant-id"
      })

  Automatically refreshes the access token using the provided refresh token.
  Returns `{:error, term}` if refresh fails.

  See `Msg.Auth` for obtaining refresh tokens via OAuth authorization code flow.

  ## Returns

  `Req.Request.t()` - Configured HTTP client ready for Graph API calls, or
  `{:error, term}` - If token refresh fails (refresh token pattern only)
  """
  @spec new(credentials() | String.t(), token_provider() | credentials()) ::
          Req.Request.t() | {:error, term()}
  def new(credentials_or_token, token_provider_or_credentials \\ &fetch_token!/1)

  def new(credentials, token_provider)
      when is_map(credentials) and is_map_key(credentials, :client_id) and
             is_function(token_provider, 1) do
    access_token = token_provider.(credentials)
    build_client(access_token)
  end

  def new(access_token, _) when is_binary(access_token) do
    build_client(access_token)
  end

  def new(refresh_token, %{client_id: _, client_secret: _, tenant_id: _} = credentials)
      when is_binary(refresh_token) do
    case Auth.refresh_access_token(refresh_token, credentials) do
      {:ok, %{access_token: access_token}} ->
        build_client(access_token)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Fetches an access token using client credentials flow.

  This is used internally by `new/1` when called with a credentials map.
  You typically don't need to call this directly.

  ## Parameters

  - `credentials` - Map with `:client_id`, `:client_secret`, and `:tenant_id`

  ## Returns

  Access token string

  ## Raises

  Raises if token fetch fails (invalid credentials, network error, etc.)
  """
  @spec fetch_token!(credentials()) :: String.t()
  def fetch_token!(%{client_id: client_id, client_secret: client_secret, tenant_id: tenant_id}) do
    OAuth2Client.new(
      client_id: client_id,
      client_secret: client_secret,
      site: "https://graph.microsoft.com",
      strategy: ClientCredentials,
      token_url: "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token"
    )
    |> OAuth2Client.put_serializer("application/json", Jason)
    |> OAuth2Client.get_token!(scope: "https://graph.microsoft.com/.default")
    |> Map.get(:token)
    |> Map.get(:access_token)
  end

  # Private helpers

  defp build_client(access_token) do
    Req.new(base_url: "https://graph.microsoft.com/v1.0")
    |> Request.put_headers([
      {"authorization", "Bearer #{access_token}"},
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ])
  end
end
