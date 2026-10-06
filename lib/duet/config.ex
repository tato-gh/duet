defmodule Duet.Config do
  @moduledoc """
  Loads duet configuration from `DUET.md`.
  """

  @default_entry %{
    command: "codex app-server",
    role: "",
    model: nil,
    reasoning_effort: nil,
    service_tier: nil,
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
    case Map.get(entry, "backend", "codex") do
      "codex" -> build_codex_entry(entry)
      "claude" -> build_claude_entry(entry)
      backend -> {:error, "Unknown backend for entry #{name}: #{inspect(backend)}"}
    end
  end

  defp build_entry(_), do: {:error, "entries item is missing required field 'name'"}

  defp build_codex_entry(%{"name" => name} = entry) do
    with :ok <- reject_keys(entry, ["permission_mode", "tools", "allowed_tools"], "codex") do
      {:ok,
       %{
         name: name,
         backend: :codex,
         command: Map.get(entry, "command", @default_entry.command),
         role: Map.get(entry, "role", @default_entry.role),
         model: normalize_optional_string(Map.get(entry, "model")),
         reasoning_effort: normalize_reasoning_effort(Map.get(entry, "reasoning_effort")),
         service_tier: normalize_service_tier(Map.get(entry, "service_tier")),
         approval_policy: Map.get(entry, "approval_policy", @default_entry.approval_policy),
         thread_sandbox: Map.get(entry, "thread_sandbox", @default_entry.thread_sandbox),
         turn_sandbox_policy:
           Map.get(entry, "turn_sandbox_policy", @default_entry.turn_sandbox_policy)
       }}
    end
  end

  defp build_claude_entry(%{"name" => name} = entry) do
    allowed =
      ~w(name backend command role model reasoning_effort permission_mode tools allowed_tools)

    command = Map.get(entry, "command", "claude")
    role = Map.get(entry, "role", "")
    model = Map.get(entry, "model")
    effort = Map.get(entry, "reasoning_effort")
    permission_mode = Map.get(entry, "permission_mode", "dontAsk")
    tools = Map.get(entry, "tools", ["Read", "Glob", "Grep"])
    allowed_tools = Map.get(entry, "allowed_tools", [])

    with :ok <- reject_keys(entry, Map.keys(entry) -- allowed, "claude"),
         :ok <- valid_setting(is_binary(command) and command != "", name, "command"),
         :ok <- valid_setting(is_binary(role), name, "role"),
         :ok <- valid_setting(is_nil(model) or (is_binary(model) and model != ""), name, "model"),
         :ok <-
           valid_setting(
             effort in [nil, "low", "medium", "high", "xhigh", "max"],
             name,
             "reasoning_effort"
           ),
         :ok <-
           valid_setting(
             permission_mode in [
               "default",
               "dontAsk",
               "acceptEdits",
               "plan",
               "auto",
               "bypassPermissions"
             ],
             name,
             "permission_mode"
           ),
         :ok <- valid_setting(string_list?(tools), name, "tools"),
         :ok <- valid_setting(string_list?(allowed_tools), name, "allowed_tools") do
      {:ok,
       %{
         name: name,
         backend: :claude,
         command: command,
         role: role,
         model: model,
         reasoning_effort: effort,
         permission_mode: permission_mode,
         tools: tools,
         allowed_tools: allowed_tools
       }}
    end
  end

  defp string_list?(values) when is_list(values),
    do: Enum.all?(values, &(is_binary(&1) and &1 != ""))

  defp string_list?(_), do: false

  defp valid_setting(true, _name, _key), do: :ok
  defp valid_setting(false, name, key), do: {:error, "Invalid #{key} for entry #{name}"}

  defp reject_keys(entry, keys, backend) do
    unsupported = Enum.filter(keys, &Map.has_key?(entry, &1))

    if unsupported == [],
      do: :ok,
      else:
        {:error,
         "Unsupported settings for #{backend} entry #{entry["name"]}: #{inspect(unsupported)}"}
  end

  defp normalize_service_tier("fast"), do: "fast"
  defp normalize_service_tier(_), do: @default_entry.service_tier

  defp normalize_reasoning_effort(effort)
       when effort in ["none", "low", "medium", "high", "xhigh", "max"],
       do: effort

  defp normalize_reasoning_effort(_), do: @default_entry.reasoning_effort

  defp normalize_optional_string(value) when is_binary(value) and value != "", do: value
  defp normalize_optional_string(_), do: nil

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
