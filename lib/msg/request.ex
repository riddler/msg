defmodule Msg.Request do
  @moduledoc """
  Provides helpers for performing Microsoft Graph API requests using Req.

  Handles common behaviors like parsing JSON, extracting errors, and optionally
  paginating across `@odata.nextLink`.
  """

  @type client :: Req.Request.t()

  @doc """
  Performs a simple GET request to the given Graph API path.

  ## Example

      Msg.Request.get(client, "/me")
  """
  @spec get(client(), String.t()) :: {:ok, map()} | {:error, any()}
  def get(%Req.Request{} = client, path) do
    client
    |> Req.get(url: path)
    |> handle_response()
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, reason}), do: {:error, reason}
end
