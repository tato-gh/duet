defmodule Duet.Config do
  @moduledoc """
  Loads duet configuration from `DUET.md`.
  """

  @default_entry %{
    command: "codex app-server",
    role: "",
    approval_policy: "never",
    thread_sandbox: "read-only",
    turn_sandbox_policy: %{
      "type" => "readOnly",
      "networkAccess" => false
    }
  }

  def config_file_path do
    Application.get_env(:duet, :config_file_path)
  end

  def set_config_file(path) when is_binary(path) do
    Application.put_env(:duet, :config_file_path, path)
    :ok
  end

  def parse(path) do
    case File.read(path) do
      {:error, :enoent} -> {:ok, default_config()}
      {:error, reason} -> {:error, "Failed to read DUET.md: #{inspect(reason)}"}
      {:ok, content} -> parse_content(content)
    end
  end

  defp parse_content(content) do
    case String.split(content, "---\n", parts: 3) do
      ["", front_matter, _body] ->
        case YamlElixir.read_from_string(front_matter) do
          {:ok, yaml} -> build_and_validate(yaml || %{})
          {:error, reason} -> {:error, "Failed to parse YAML: #{inspect(reason)}"}
        end

      _ ->
        {:error, "DUET.md must have YAML front matter (--- ... ---)"}
    end
  end

  defp build_and_validate(yaml) when is_map(yaml) do
    with :ok <- validate_keys(yaml),
         {:ok, entries} <- build_entries(Map.get(yaml, "entries", [])),
         :ok <- validate_unique_names(entries) do
      {:ok, %{node_name: Map.get(yaml, "node_name", default_node_name()), entries: entries}}
    end
  end

  defp build_and_validate(_), do: {:error, "DUET.md front matter must be a map"}

  defp build_entries(entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case build_entry(entry) do
        {:ok, built} -> {:cont, {:ok, acc ++ [built]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_entries(_), do: {:error, "entries must be a list"}

  defp build_entry(%{"name" => name} = entry) when is_binary(name) and name != "" do
    {:ok,
     %{
       name: name,
       command: Map.get(entry, "command", @default_entry.command),
       role: Map.get(entry, "role", @default_entry.role),
       approval_policy: Map.get(entry, "approval_policy", @default_entry.approval_policy),
       thread_sandbox: Map.get(entry, "thread_sandbox", @default_entry.thread_sandbox),
       turn_sandbox_policy:
         Map.get(entry, "turn_sandbox_policy", @default_entry.turn_sandbox_policy)
     }}
  end

  defp build_entry(_), do: {:error, "entries item is missing required field 'name'"}

  defp validate_keys(yaml) do
    allowed = ["node_name", "entries"]
    unknown = Map.keys(yaml) -- allowed

    if unknown == [] do
      :ok
    else
      {:error, "Unknown DUET.md keys: #{inspect(unknown)}"}
    end
  end

  defp validate_unique_names(entries) do
    names = Enum.map(entries, & &1.name)
    duplicates = names -- Enum.uniq(names)

    if duplicates == [] do
      :ok
    else
      {:error, "Duplicate entry names: #{inspect(duplicates)}"}
    end
  end

  defp default_config do
    %{node_name: default_node_name(), entries: []}
  end

  defp default_node_name do
    {:ok, hostname} = :inet.gethostname()
    "duet@#{hostname}"
  end
end
