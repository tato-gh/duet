defmodule Duet.Poller do
  @moduledoc """
  管理リソースは指定先フォルダの動静
  """

  use GenServer
  require Logger

  @topic "duet:events"

  # state:
  #   duetflow_path:       監視対象の DUETFLOW.md パス
  #   config:              %{command, diff_command, poll_interval, prompt}
  #   prev_duetflow_mtime: 前回の DUETFLOW.md mtime
  #   prev_diff_hash:      前回の diff の sha256 ハッシュ（nil = 初回）
  #   prev_diff_empty:     前回の diff が空だったか（empty→non-empty の検出用）

  # --- Public API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_command do
    GenServer.call(__MODULE__, :get_command)
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    duetflow_path = Duet.Duetflow.duetflow_file_path()

    case parse_duetflow(duetflow_path) do
      {:ok, config} ->
        mtime = read_mtime(duetflow_path)
        schedule_poll(0)

        {:ok,
         %{
           duetflow_path: duetflow_path,
           config: config,
           prev_duetflow_mtime: mtime,
           prev_diff_hash: nil,
           prev_diff_empty: true,
           prev_diff: ""
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_command, _from, state) do
    {:reply, state.config.command, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = check_duetflow(state)
    state = check_diff(state)
    schedule_poll(state.config.poll_interval)
    {:noreply, state}
  end

  # --- Private ---

  defp check_duetflow(state) do
    new_mtime = read_mtime(state.duetflow_path)

    if new_mtime == state.prev_duetflow_mtime do
      state
    else
      case parse_duetflow(state.duetflow_path) do
        {:error, reason} ->
          Logger.warning("Failed to reload DUETFLOW.md: #{reason}")
          %{state | prev_duetflow_mtime: new_mtime}

        {:ok, new_config} ->
          old = state.config

          cond do
            old.command != new_config.command or
              old.diff_command != new_config.diff_command or
                old.poll_interval != new_config.poll_interval or
                  old.include_untracked != new_config.include_untracked ->
              broadcast(:config_changed, %{config: new_config})

            old.prompt != new_config.prompt ->
              broadcast(:prompt_changed, %{prompt: new_config.prompt})

            true ->
              :ok
          end

          %{state | config: new_config, prev_duetflow_mtime: new_mtime}
      end
    end
  end

  defp check_diff(state) do
    cwd = Path.dirname(state.duetflow_path)
    diff = run_diff(state.config.diff_command, cwd, state.config.include_untracked)
    new_hash = :crypto.hash(:sha256, diff) |> Base.encode16()

    if new_hash == state.prev_diff_hash do
      state
    else
      new_empty = diff == ""

      cond do
        new_empty ->
          broadcast(:context_reset, %{prompt: state.config.prompt})

        state.prev_diff_empty ->
          broadcast(:diff_started, %{prompt: state.config.prompt, diff: diff})

        true ->
          delta = diff_delta(state.prev_diff, diff)
          if delta != "", do: broadcast(:diff_changed, %{diff: delta})
      end

      %{state | prev_diff_hash: new_hash, prev_diff_empty: new_empty, prev_diff: diff}
    end
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp read_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> mtime
      _ -> nil
    end
  end

  @default_config %{
    command: "codex app-server",
    diff_command: "git diff HEAD",
    poll_interval: 1000,
    include_untracked: false,
    prompt: ""
  }

  defp parse_duetflow(path) do
    case File.read(path) do
      {:error, :enoent} ->
        {:ok, @default_config}

      {:error, reason} ->
        {:error, "Failed to read DUETFLOW.md: #{reason}"}

      {:ok, content} ->
        parse_duetflow_content(content)
    end
  end

  defp parse_duetflow_content(content) do
    {front_matter, prompt} =
      case String.split(content, "---\n", parts: 3) do
        ["", fm, body] -> {fm, String.trim(body)}
        _ -> {"", content}
      end

    config =
      front_matter
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, ": ", parts: 2) do
          [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
          _ -> acc
        end
      end)

    {:ok,
     %{
       command: Map.get(config, "command", @default_config.command),
       diff_command: Map.get(config, "diff_command", @default_config.diff_command),
       poll_interval: config |> Map.get("poll_interval", "1000") |> String.to_integer(),
       include_untracked: config |> Map.get("include_untracked", "false") |> (&(&1 == "true")).(),
       prompt: prompt
     }}
  end

  defp run_diff(diff_command, cwd, include_untracked) do
    {tracked, _} = System.cmd("sh", ["-c", diff_command <> " -- ."], cd: cwd, stderr_to_stdout: false)
    untracked =
      if include_untracked do
        {out, _} = System.cmd(
          "sh",
          ["-c", ~s(git ls-files --others --exclude-standard -- . | while IFS= read -r f; do git diff --no-index -- /dev/null "$f" 2>/dev/null; done)],
          cd: cwd,
          stderr_to_stdout: false
        )
        out
      else
        ""
      end
    filter_duetflow(tracked <> untracked)
  end

  # DUETFLOW.md に関するファイルセクションをまるごと除外する
  defp filter_duetflow(diff_output) do
    {kept, _} =
      diff_output
      |> String.split("\n")
      |> Enum.reduce({[], false}, &filter_line/2)

    kept |> Enum.reverse() |> Enum.join("\n")
  end

  defp filter_line("diff --git" <> _ = line, {acc, _skip}) do
    skip = String.contains?(line, "DUETFLOW.md")
    {if(skip, do: acc, else: [line | acc]), skip}
  end

  defp filter_line(_line, {acc, true}), do: {acc, true}
  defp filter_line(line, {acc, false}), do: {[line | acc], false}

  # 前回 diff と現在 diff を比較し、変化したファイルセクションのみ返す
  defp diff_delta(prev_diff, new_diff) do
    prev_sections = parse_diff_sections(prev_diff)

    new_diff
    |> parse_diff_sections()
    |> Enum.flat_map(fn {file, content} ->
      prev_lines = MapSet.new(String.split(prev_sections[file] || "", "\n"))
      [_header | rest] = String.split(content, "\n")
      delta = Enum.reject(rest, &MapSet.member?(prev_lines, &1))
      has_content = Enum.any?(delta, &(String.starts_with?(&1, "+") and not String.starts_with?(&1, "+++")))
      if has_content, do: [file <> "\n" <> Enum.join(delta, "\n")], else: []
    end)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp parse_diff_sections(diff) do
    diff
    |> String.split(~r/(?=^diff --git )/m)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn section ->
      file = section |> String.split("\n") |> hd() |> String.trim()
      {file, section}
    end)
    |> Map.new()
  end

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(Duet.PubSub, @topic, {event, payload})
  end
end
