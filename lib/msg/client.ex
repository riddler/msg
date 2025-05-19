defmodule Msg.Client do
  @moduledoc """
  Responsible for handling authentication and request setup for
  interacting with the Microsoft Graph API using the `req` and `oauth2` libraries.

  ## Example

      creds = %{
        client_id: "your-client-id",
        client_secret: "your-client-secret",
        tenant_id: "your-tenant-id"
      }

      client = Msg.Client.new(creds)
      Req.get!(client, "/me")

      # With custom token provider for testability
      token_provider = fn creds -> "stub-token" end
      client = Msg.Client.new(creds, token_provider)

  ## References
  - Microsoft Graph REST API: https://learn.microsoft.com/en-us/graph/api/overview
  - OAuth2 client credentials: https://learn.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-client-creds-grant-flow
  """

  @type credentials :: %{
          required(:client_id) => String.t(),
          required(:client_secret) => String.t(),
          required(:tenant_id) => String.t()
        }

  @type token_provider :: (credentials() -> String.t())

  @spec new(credentials(), token_provider()) :: Req.Request.t()
  def new(creds, token_provider \\ &fetch_token!/1) do
    access_token = token_provider.(creds)

    Req.new(base_url: "https://graph.microsoft.com/v1.0")
    |> Req.Request.put_headers([
      {"authorization", "Bearer #{access_token}"},
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ])
  end

  @spec fetch_token!(credentials()) :: String.t()
  def fetch_token!(%{client_id: client_id, client_secret: client_secret, tenant_id: tenant_id}) do
    OAuth2.Client.new(
      client_id: client_id,
      client_secret: client_secret,
      site: "https://graph.microsoft.com",
      strategy: OAuth2.Strategy.ClientCredentials,
      token_url: "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token"
    )
    |> OAuth2.Client.put_serializer("application/json", Jason)
    |> OAuth2.Client.get_token!(scope: "https://graph.microsoft.com/.default")
    |> Map.get(:token)
    |> Map.get(:access_token)
  end
end
