defmodule Duet.Duetflow do
  @moduledoc """
  Loads duetflow configuration and prompt from DUETFLOW.md.
  """

  @default_diff_watch %{
    enabled: true,
    command: "codex app-server",
    diff_command: "git diff HEAD",
    poll_interval: 1000,
    include_untracked: false,
    file_change_approval: "reject",
    prompt: ""
  }

  def duetflow_file_path do
    Application.get_env(:duet, :duetflow_file_path)
  end

  def set_duetflow_file(path) when is_binary(path) do
    Application.put_env(:duet, :duetflow_file_path, path)
    :ok
  end

  def parse(path) do
    case File.read(path) do
      {:error, :enoent} -> {:ok, default_config()}
      {:error, reason} -> {:error, "Failed to read DUETFLOW.md: #{inspect(reason)}"}
      {:ok, content} -> parse_content(content)
    end
  end

  defp parse_content(content) do
    case String.split(content, "---\n", parts: 3) do
      ["", fm, _body] ->
        case YamlElixir.read_from_string(fm) do
          {:ok, yaml} -> build_and_validate(yaml)
          {:error, reason} -> {:error, "Failed to parse YAML: #{inspect(reason)}"}
        end

      _ ->
        {:error, "DUETFLOW.md must have YAML front-matter (--- ... ---)"}
    end
  end

  defp build_and_validate(yaml) do
    with {:ok, erpc_entries} <- build_erpc_channel(Map.get(yaml, "erpc_channel", [])) do
      hostname = default_hostname()
      node_name = Map.get(yaml, "node_name", "duet@#{hostname}")
      diff_watch = build_diff_watch(Map.get(yaml, "diff_watch", %{}))
      config = %{node_name: node_name, diff_watch: diff_watch, erpc_channel: erpc_entries}

      names = Enum.map(erpc_entries, & &1.name)
      duplicates = names -- Enum.uniq(names)

      if duplicates == [] do
        {:ok, config}
      else
        {:error, "Duplicate erpc_channel entry names: #{inspect(duplicates)}"}
      end
    end
  end

  defp build_diff_watch(dw) when is_map(dw) do
    %{
      enabled: Map.get(dw, "enabled", true),
      command: Map.get(dw, "command", @default_diff_watch.command),
      diff_command: Map.get(dw, "diff_command", @default_diff_watch.diff_command),
      poll_interval: Map.get(dw, "poll_interval", @default_diff_watch.poll_interval),
      include_untracked: Map.get(dw, "include_untracked", @default_diff_watch.include_untracked),
      file_change_approval:
        Map.get(dw, "file_change_approval", @default_diff_watch.file_change_approval),
      prompt: Map.get(dw, "prompt", "")
    }
  end

  defp build_diff_watch(_), do: @default_diff_watch

  defp build_erpc_channel(entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn e, {:ok, acc} ->
      case Map.fetch(e, "name") do
        {:ok, name} ->
          entry = %{
            name: name,
            enabled: Map.get(e, "enabled", true),
            command: Map.get(e, "command", "codex app-server"),
            role: Map.get(e, "role", "")
          }

          {:cont, {:ok, acc ++ [entry]}}

        :error ->
          {:halt, {:error, "erpc_channel entry is missing required field 'name'"}}
      end
    end)
  end

  defp build_erpc_channel(_), do: {:ok, []}

  defp default_hostname do
    {:ok, hostname} = :inet.gethostname()
    to_string(hostname)
  end

  defp default_config do
    %{
      node_name: "duet@#{default_hostname()}",
      diff_watch: @default_diff_watch,
      erpc_channel: []
    }
  end
end
