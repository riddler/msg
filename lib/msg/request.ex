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

  @doc """
  Converts a map with snake_case atom keys to camelCase string keys for the Graph API.

  Handles special OData keys by converting `_odata_` to `@odata.`.

  ## Examples

      iex> Msg.Request.convert_keys(%{display_name: "Test", mail_enabled: true})
      %{"displayName" => "Test", "mailEnabled" => true}

      iex> Msg.Request.convert_keys(%{owners_odata_bind: ["user-1"]})
      %{"owners@odata.bind" => ["user-1"]}
  """
  @spec convert_keys(map()) :: map()
  def convert_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {convert_key(key), convert_value(value)}
    end)
  end

  defp convert_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> convert_key()
  end

  defp convert_key(key) when is_binary(key) do
    # Handle _odata_ pattern first (e.g., owners_odata_bind -> owners@odata.bind)
    key
    |> String.replace("_odata_", "@odata.")
    |> snake_to_camel()
  end

  defp convert_value(value) when is_map(value), do: convert_keys(value)
  defp convert_value(value) when is_list(value), do: Enum.map(value, &convert_value/1)
  defp convert_value(value), do: value

  defp snake_to_camel(string) do
    # Don't convert if it contains @odata. (already handled)
    if String.contains?(string, "@odata.") do
      string
    else
      [first | rest] =
        string
        |> String.split("_")

      Enum.join([first | Enum.map(rest, &String.capitalize/1)])
    end
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, %{status: status, body: body}}
  end

  defp handle_response({:error, reason}), do: {:error, reason}
end
