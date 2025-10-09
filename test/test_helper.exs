# Load environment variables from .env file for integration tests
if File.exists?(".env") do
  File.read!(".env")
  |> String.split("\n", trim: true)
  |> Enum.reject(&String.starts_with?(&1, "#"))
  |> Enum.each(fn line ->
    case String.split(line, "=", parts: 2) do
      ["export " <> key, value] ->
        # Remove quotes if present
        clean_value = String.trim(value, "\"")
        System.put_env(key, clean_value)

      [key, value] ->
        clean_value = String.trim(value, "\"")
        System.put_env(key, clean_value)

      _ ->
        :ok
    end
  end)
end

ExUnit.start()
