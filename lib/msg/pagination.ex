defmodule Msg.Pagination do
  @moduledoc """
  Shared pagination utilities for Microsoft Graph API list operations.
  """

  alias Msg.Request

  @doc """
  Fetches a single page from the Graph API.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `path` - API path to fetch
  - `query_params` - List of query parameter tuples

  ## Returns

  - `{:ok, %{items: [item], next_link: url | nil}}` - Page data with optional next link
  - `{:error, term}` - Error
  """
  @spec fetch_page(Req.Request.t(), String.t(), keyword()) ::
          {:ok, %{items: [map()], next_link: String.t() | nil}} | {:error, term()}
  def fetch_page(client, path, query_params) do
    url = if query_params == [], do: path, else: path <> "?" <> URI.encode_query(query_params)

    case Request.get(client, url) do
      {:ok, %{"value" => items} = response} ->
        next_link = Map.get(response, "@odata.nextLink")
        {:ok, %{items: items, next_link: next_link}}

      error ->
        error
    end
  end

  @doc """
  Recursively fetches all pages following @odata.nextLink.

  ## Parameters

  - `client` - Authenticated Req.Request client
  - `next_link` - Next page URL (or nil to stop)
  - `acc` - Accumulated items from previous pages

  ## Returns

  - `{:ok, [item]}` - All items from all pages
  - `{:error, term}` - Error
  """
  @spec fetch_all_pages(Req.Request.t(), String.t() | nil, [map()]) ::
          {:ok, [map()]} | {:error, term()}
  def fetch_all_pages(client, next_link, acc) when is_binary(next_link) do
    # Extract the path from the full URL
    uri = URI.parse(next_link)
    # Remove /v1.0 prefix since it's already in base_url
    path = String.replace_prefix(uri.path, "/v1.0", "")
    path = path <> if uri.query, do: "?" <> uri.query, else: ""

    case Request.get(client, path) do
      {:ok, %{"value" => items} = response} ->
        new_acc = acc ++ items

        case Map.get(response, "@odata.nextLink") do
          nil ->
            {:ok, new_acc}

          new_next_link ->
            fetch_all_pages(client, new_next_link, new_acc)
        end

      error ->
        error
    end
  end

  def fetch_all_pages(_, nil, acc), do: {:ok, acc}
end
