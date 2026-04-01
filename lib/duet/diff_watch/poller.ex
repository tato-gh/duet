defmodule Duet.DiffWatch.Poller do
  @moduledoc """
  管理リソースは git diff の変動監視。
  設定変更の監視は Duet.ConfigWatcher が担う。
  """

  use GenServer
  require Logger

  @topic "duet:events"

  # --- Public API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Duet.PubSub, @topic)
    config = Duet.ConfigWatcher.get_config().diff_watch
    duetflow_path = Duet.Duetflow.duetflow_file_path()
    schedule_poll(0)

    {:ok,
     %{
       duetflow_path: duetflow_path,
       config: config,
       prev_diff_hash: nil,
       prev_diff_empty: true,
       prev_diff: ""
     }}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = check_diff(state)
    schedule_poll(state.config.poll_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info({:config_changed, %{config: new_config}}, state) do
    {:noreply, %{state | config: new_config}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

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

  defp run_diff(diff_command, cwd, include_untracked) do
    {tracked, _} =
      System.cmd("sh", ["-c", diff_command <> " -- ."], cd: cwd, stderr_to_stdout: false)

    untracked =
      if include_untracked do
        {out, _} =
          System.cmd(
            "sh",
            [
              "-c",
              ~s(git ls-files --others --exclude-standard -- . | while IFS= read -r f; do git diff --no-index -- /dev/null "$f" 2>/dev/null; done)
            ],
            cd: cwd,
            stderr_to_stdout: false
          )

        out
      else
        ""
      end

    filter_duetflow(tracked <> untracked)
  end

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

  defp diff_delta(prev_diff, new_diff) do
    prev_sections = parse_diff_sections(prev_diff)

    new_diff
    |> parse_diff_sections()
    |> Enum.flat_map(fn {file, content} ->
      prev_lines = MapSet.new(String.split(prev_sections[file] || "", "\n"))
      [_header | rest] = String.split(content, "\n")
      delta = Enum.reject(rest, &MapSet.member?(prev_lines, &1))

      has_content =
        Enum.any?(delta, &(String.starts_with?(&1, "+") and not String.starts_with?(&1, "+++")))

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
