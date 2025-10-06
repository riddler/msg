# Script to find the Test Group ID
# Run with: mix run scripts/find_test_group.exs

creds = %{
  client_id: System.fetch_env!("MICROSOFT_CLIENT_ID"),
  client_secret: System.fetch_env!("MICROSOFT_CLIENT_SECRET"),
  tenant_id: System.fetch_env!("MICROSOFT_TENANT_ID")
}

IO.puts("Creating client and fetching groups...")
client = Msg.Client.new(creds)

case Msg.Request.get(client, "/groups") do
  {:ok, %{"value" => groups}} ->
    IO.puts("\nFound #{length(groups)} groups:")
    IO.puts(String.duplicate("-", 80))

    test_group =
      Enum.find(groups, fn group ->
        group["displayName"] == "Test Group"
      end)

    case test_group do
      nil ->
        IO.puts("\n❌ 'Test Group' not found!")
        IO.puts("\nAvailable groups:")

        Enum.each(groups, fn group ->
          IO.puts("  - #{group["displayName"]} (ID: #{group["id"]})")
        end)

      group ->
        IO.puts("\n✅ Found 'Test Group'!")
        IO.puts("\nGroup Details:")
        IO.puts("  Display Name: #{group["displayName"]}")
        IO.puts("  ID: #{group["id"]}")
        IO.puts("  Mail: #{group["mail"] || "N/A"}")
        IO.puts("  Description: #{group["description"] || "N/A"}")
        IO.puts("\nAdd this to your environment:")
        IO.puts("  export MICROSOFT_TEST_GROUP_ID=\"#{group["id"]}\"")
    end

  {:error, error} ->
    IO.puts("\n❌ Error fetching groups:")
    IO.inspect(error, pretty: true)
end
