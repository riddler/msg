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

    Req.new(url: "https://graph.microsoft.com/v1.0")
    |> Req.Request.put_headers([
      {"authorization", "Bearer #{access_token}"},
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ])
  end

  @spec fetch_token!(credentials()) :: String.t()
  def fetch_token!(%{client_id: id, client_secret: secret, tenant_id: tenant}) do
    OAuth2.Client.new([
      client_id: id,
      client_secret: secret,
      site: "https://login.microsoftonline.com/#{tenant}",
      authorize_url: "/oauth2/v2.0/authorize",
      token_url: "/oauth2/v2.0/token",
      params: [scope: "https://graph.microsoft.com/.default"]
    ])
    |> OAuth2.Client.get_token!()
    |> Map.get(:token)
    |> Map.get(:access_token)
  end
end
