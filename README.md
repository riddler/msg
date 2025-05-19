# Microsoft Graph for Elixir

`msg` is an Elixir library for accessing Microsoft 365 data using the [Microsoft Graph API](https://learn.microsoft.com/en-us/graph/api/overview).

This library is designed for applications that use client credentials (application-only).

Documentation can be found at [https://hexdocs.com/msg](https://hexdocs.com/msg).

---

## Installation

This package is [available in Hex](https://hex.pm/packages/msg), and can be installed by adding `msg` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:msg, "~> 0.1.0"}
  ]
end
```

## Example Usage

```elixir
creds = %{
  client_id: System.get_env("MICROSOFT_CLIENT_ID"),
  client_secret: System.get_env("MICROSOFT_CLIENT_SECRET"),
  tenant_id: System.get_env("MICROSOFT_TENANT_ID")
}

client = Msg.Client.new(creds)
{:ok, %{"value" => users}} = Msg.Users.list(client)
```

## Features

* Built on top of Req for HTTP requests
* OAuth2 client credentials flow via oauth2

## License

MIT License. See [LICENSE](/LICENSE) for details.
