creds = %{
  client_id: System.fetch_env!("MICROSOFT_CLIENT_ID"),
  client_secret: System.fetch_env!("MICROSOFT_CLIENT_SECRET"),
  tenant_id: System.fetch_env!("MICROSOFT_TENANT_ID")
}

client = Msg.Client.new(creds)
