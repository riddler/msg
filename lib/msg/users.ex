defmodule Msg.Users do
  @moduledoc """
  Provides functions for interacting with the Microsoft Graph `/users` endpoint.

  ## Example

      client = Msg.Client.new(creds)
      {:ok, users} = Msg.Users.list(client)
  """

  alias Msg.Request

  @doc """
  Lists all users in the organization.

  Corresponds to: [GET /users]
  https://learn.microsoft.com/en-us/graph/api/user-list?view=graph-rest-1.0&tabs=http
  """
  @spec list(Req.Request.t()) :: {:ok, map()} | {:error, any()}
  def list(client) do
    Request.get(client, "/users")
  end
end
