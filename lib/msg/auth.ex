defmodule Msg.Auth do
  @moduledoc """
  OAuth helper functions for Microsoft Identity Platform.

  Provides utilities for the OAuth authorization code flow, enabling
  delegated permissions (user-context authentication) in addition to
  the client credentials flow (application-only authentication).

  ## OAuth Flows

  ### Client Credentials (Application-Only)
  See `Msg.Client.new/1` for application-only authentication using
  app permissions like `User.ReadWrite.All`, `Group.ReadWrite.All`.

  ### Authorization Code (Delegated Permissions)
  Use the functions in this module for delegated permissions like
  `Calendars.ReadWrite.Shared` which require user context:

  1. Generate authorization URL
  2. User signs in and grants consent
  3. Exchange authorization code for tokens
  4. Use refresh token to get new access tokens

  ## Example

      # Step 1: Generate authorization URL
      credentials = %{
        client_id: "app-id",
        tenant_id: "tenant-id"
      }

      url = Msg.Auth.get_authorization_url(credentials,
        redirect_uri: "https://myapp.com/auth/callback",
        scopes: ["Calendars.ReadWrite.Shared", "offline_access"],
        state: "csrf-token"
      )

      # Step 2: Redirect user to URL, they sign in and approve
      # Microsoft redirects back to: https://myapp.com/auth/callback?code=...&state=...

      # Step 3: Exchange code for tokens
      credentials = %{
        client_id: "app-id",
        client_secret: "secret",
        tenant_id: "tenant-id"
      }

      {:ok, tokens} = Msg.Auth.exchange_code_for_tokens(
        "authorization-code-here",
        credentials,
        redirect_uri: "https://myapp.com/auth/callback"
      )

      # Store tokens.refresh_token securely (encrypted in database)

      # Step 4: Use refresh token to get new access tokens
      {:ok, new_tokens} = Msg.Auth.refresh_access_token(
        tokens.refresh_token,
        credentials
      )

      # Create client with access token
      client = Msg.Client.new(new_tokens.access_token)

  ## Security Notes

  - Always use HTTPS for redirect URIs
  - Validate the `state` parameter to prevent CSRF attacks
  - Store refresh tokens encrypted in your database
  - Never log or commit tokens to version control
  - Handle token rotation (Microsoft may return new refresh tokens)

  ## References

  - [Microsoft Identity Platform - Authorization code flow](https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow)
  - [Microsoft Graph - Get access on behalf of a user](https://learn.microsoft.com/en-us/graph/auth-v2-user)
  """

  alias OAuth2.AccessToken
  alias OAuth2.Client, as: OAuth2Client
  alias OAuth2.Response

  @type credentials :: %{
          required(:client_id) => String.t(),
          required(:client_secret) => String.t(),
          required(:tenant_id) => String.t()
        }

  @type credentials_without_secret :: %{
          required(:client_id) => String.t(),
          required(:tenant_id) => String.t()
        }

  @type token_response :: %{
          access_token: String.t(),
          token_type: String.t(),
          expires_in: integer(),
          scope: String.t(),
          refresh_token: String.t()
        }

  @doc """
  Generates the Microsoft OAuth authorization URL for user sign-in.

  This is the first step in the authorization code flow. Redirect the user
  to this URL, where they will sign in and grant permissions. Microsoft will
  then redirect back to your `redirect_uri` with an authorization code.

  ## Parameters

  - `credentials` - Map with `:client_id` and `:tenant_id` (no secret needed)
  - `opts` - Keyword list of options:
    - `:redirect_uri` (required) - HTTPS URL where Microsoft redirects after auth
    - `:scopes` (required) - List of permission scopes to request
    - `:state` (optional) - Random string for CSRF protection (recommended)

  ## Returns

  Authorization URL string to redirect the user to.

  ## Examples

      url = Msg.Auth.get_authorization_url(
        %{client_id: "app-id", tenant_id: "tenant-id"},
        redirect_uri: "https://myapp.com/auth/callback",
        scopes: ["Calendars.ReadWrite.Shared", "Group.ReadWrite.All", "offline_access"],
        state: "random-csrf-token"
      )

      # Redirect user to this URL
      # After sign-in, Microsoft redirects to:
      # https://myapp.com/auth/callback?code=...&state=random-csrf-token

  ## Important

  - Always include `"offline_access"` scope to receive a refresh token
  - Validate the `state` parameter in your callback to prevent CSRF attacks
  - The redirect URI must be registered in your Azure AD app configuration
  """
  @spec get_authorization_url(credentials_without_secret(), keyword()) :: String.t()
  def get_authorization_url(%{client_id: client_id, tenant_id: tenant_id}, opts) do
    redirect_uri = Keyword.fetch!(opts, :redirect_uri)
    scopes = Keyword.fetch!(opts, :scopes)
    state = Keyword.get(opts, :state)

    query_params =
      [
        client_id: client_id,
        response_type: "code",
        redirect_uri: redirect_uri,
        scope: Enum.join(scopes, " "),
        response_mode: "query"
      ]
      |> maybe_add_state(state)
      |> URI.encode_query()

    "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/authorize?#{query_params}"
  end

  @doc """
  Exchanges an authorization code for access and refresh tokens.

  After the user signs in and Microsoft redirects to your callback URL with
  an authorization code, call this function to exchange the code for tokens.

  ## Parameters

  - `code` - Authorization code from Microsoft's callback
  - `credentials` - Map with `:client_id`, `:client_secret`, and `:tenant_id`
  - `opts` - Keyword list of options:
    - `:redirect_uri` (required) - Must match the URI used in authorization request

  ## Returns

  - `{:ok, token_response}` - Map with access_token, refresh_token, expires_in, etc.
  - `{:error, error}` - OAuth error response

  ## Examples

      {:ok, tokens} = Msg.Auth.exchange_code_for_tokens(
        "authorization-code-from-callback",
        %{client_id: "app-id", client_secret: "secret", tenant_id: "tenant-id"},
        redirect_uri: "https://myapp.com/auth/callback"
      )

      # Store tokens.refresh_token securely (encrypted!)
      # Use tokens.access_token to create client:
      client = Msg.Client.new(tokens.access_token)

  ## Error Handling

  Common errors:
  - `invalid_grant` - Code expired or already used (codes expire in 10 minutes)
  - `invalid_client` - Invalid client_id or client_secret
  - `redirect_uri_mismatch` - redirect_uri doesn't match authorization request
  """
  @spec exchange_code_for_tokens(String.t(), credentials(), keyword()) ::
          {:ok, token_response()} | {:error, OAuth2.Response.t() | term()}
  def exchange_code_for_tokens(code, credentials, opts) do
    redirect_uri = Keyword.fetch!(opts, :redirect_uri)

    %{client_id: client_id, client_secret: client_secret, tenant_id: tenant_id} = credentials

    client =
      OAuth2Client.new(
        client_id: client_id,
        client_secret: client_secret,
        site: "https://graph.microsoft.com",
        token_url: "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token",
        redirect_uri: redirect_uri
      )
      |> OAuth2Client.put_serializer("application/json", Jason)

    case OAuth2Client.get_token(client, code: code, grant_type: "authorization_code") do
      {:ok, %OAuth2Client{token: token}} ->
        {:ok, format_token_response(token)}

      {:error, %Response{} = response} ->
        {:error, response}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Refreshes an access token using a refresh token.

  Refresh tokens are long-lived and can be used to obtain new access tokens
  without requiring the user to sign in again. Call this function before the
  access token expires (typically every hour).

  ## Parameters

  - `refresh_token` - Valid refresh token from a previous token exchange
  - `credentials` - Map with `:client_id`, `:client_secret`, and `:tenant_id`
  - `opts` - Keyword list of options:
    - `:scopes` (optional) - List of scopes to request (defaults to original scopes)

  ## Returns

  - `{:ok, token_response}` - Map with new access_token, possibly new refresh_token, expires_in, etc.
  - `{:error, error}` - OAuth error response

  ## Examples

      {:ok, new_tokens} = Msg.Auth.refresh_access_token(
        stored_refresh_token,
        %{client_id: "app-id", client_secret: "secret", tenant_id: "tenant-id"}
      )

      # Microsoft may return a new refresh token (token rotation)
      # Always update your stored refresh token:
      if Map.has_key?(new_tokens, :refresh_token) do
        update_stored_refresh_token(new_tokens.refresh_token)
      end

      # Use new access token
      client = Msg.Client.new(new_tokens.access_token)

  ## Token Rotation

  Microsoft may return a new refresh token in the response. Always check for
  `refresh_token` in the response and update your stored token if present.

  ## Error Handling

  Common errors:
  - `invalid_grant` - Refresh token expired or revoked (requires user to re-authenticate)
  - `invalid_client` - Invalid client credentials
  """
  @spec refresh_access_token(String.t(), credentials(), keyword()) ::
          {:ok, token_response()} | {:error, OAuth2.Response.t() | term()}
  def refresh_access_token(refresh_token, credentials, opts \\ []) do
    %{client_id: client_id, client_secret: client_secret, tenant_id: tenant_id} = credentials

    token_url = "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token"

    # Build request parameters
    params = [
      grant_type: "refresh_token",
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token
    ]

    # Add optional scopes
    params =
      case Keyword.get(opts, :scopes) do
        nil -> params
        scopes -> Keyword.put(params, :scope, Enum.join(scopes, " "))
      end

    # Make direct HTTP request to token endpoint
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    body = URI.encode_query(params)

    case Req.post(token_url, headers: headers, body: body) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok,
         %{
           access_token: response_body["access_token"],
           token_type: response_body["token_type"],
           expires_in: response_body["expires_in"],
           scope: Map.get(response_body, "scope", ""),
           refresh_token: Map.get(response_body, "refresh_token", refresh_token)
         }}

      {:ok, %{status: status, body: error_body}} ->
        {:error, %{status: status, body: error_body}}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets an access token using client credentials (application-only) flow.

  This is similar to `Msg.Client.fetch_token!/1` but returns token metadata
  for lifecycle management, making it suitable for TokenManager implementations.

  ## Parameters

  - `credentials` - Map with `:client_id`, `:client_secret`, and `:tenant_id`

  ## Returns

  - `{:ok, token_response}` - Map with access_token, expires_in, and token_type
  - `{:error, error}` - OAuth error response

  ## Examples

      {:ok, token_info} = Msg.Auth.get_app_token(%{
        client_id: "app-id",
        client_secret: "secret",
        tenant_id: "tenant-id"
      })

      # Store token with accurate expiry
      expires_at = DateTime.add(DateTime.utc_now(), token_info.expires_in, :second)
      store_token(token_info.access_token, expires_at)

  ## Difference from `Msg.Client.fetch_token!/1`

  - Returns `{:ok, metadata}` instead of raising
  - Includes `expires_in` for accurate lifecycle management
  - Designed for token managers, not immediate client creation
  """
  @spec get_app_token(credentials()) ::
          {:ok, %{access_token: String.t(), expires_in: integer(), token_type: String.t()}}
          | {:error, term()}
  def get_app_token(%{client_id: client_id, client_secret: client_secret, tenant_id: tenant_id}) do
    token_url = "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token"

    params = [
      grant_type: "client_credentials",
      client_id: client_id,
      client_secret: client_secret,
      scope: "https://graph.microsoft.com/.default"
    ]

    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    body = URI.encode_query(params)

    case Req.post(token_url, headers: headers, body: body) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok,
         %{
           access_token: response_body["access_token"],
           token_type: response_body["token_type"],
           expires_in: response_body["expires_in"]
         }}

      {:ok, %{status: status, body: error_body}} ->
        {:error, %{status: status, body: error_body}}

      {:error, error} ->
        {:error, error}
    end
  end

  # Private helpers

  defp maybe_add_state(params, nil), do: params
  defp maybe_add_state(params, state), do: Keyword.put(params, :state, state)

  defp format_token_response(%AccessToken{} = token) do
    %{
      access_token: token.access_token,
      token_type: token.token_type,
      expires_in: token.expires_at - :os.system_time(:second),
      scope: Map.get(token.other_params, "scope", ""),
      refresh_token: token.refresh_token
    }
  end
end
