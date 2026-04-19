defmodule Duet.AppServerCommon do
  @moduledoc false

  require Logger

  @error_like ~r/\b(error|warn|warning|failed|fatal|panic|exception)\b/i
  @utf8_locale "C.UTF-8"

  def decode_and_process(line, state, process_fun, log_prefix) when is_function(process_fun, 2) do
    normalized = normalize_utf8(line)

    try do
      msg = JSON.decode!(normalized)
      process_fun.(msg, state)
    rescue
      _ ->
        log_non_json(log_prefix, normalized)
        state
    end
  end

  def send_rpc(state, method, params) do
    msg = %{method: method, id: state.rpc_id, params: params}
    Port.command(state.port, JSON.encode!(msg) <> "\n")
    %{state | rpc_id: state.rpc_id + 1}
  end

  def send_notification(state, method, params) do
    msg = %{method: method, params: params}
    Port.command(state.port, JSON.encode!(msg) <> "\n")
    state
  end

  def send_response(state, id, result) do
    Port.command(state.port, JSON.encode!(%{id: id, result: result}) <> "\n")
  end

  def start_app_server(command, cwd, line_bytes) do
    bash = System.find_executable("bash") || raise "bash not found in PATH"

    Port.open(
      {:spawn_executable, String.to_charlist(bash)},
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [~c"-lc", String.to_charlist(command)],
        cd: String.to_charlist(cwd),
        env: [
          {~c"LANG", String.to_charlist(@utf8_locale)},
          {~c"LC_ALL", String.to_charlist(@utf8_locale)}
        ],
        line: line_bytes
      ]
    )
  end

  def build_non_interactive_answers(
        %{"questions" => questions},
        non_interactive_answer
      )
      when is_list(questions) and is_binary(non_interactive_answer) do
    result =
      Enum.reduce_while(questions, %{}, fn
        %{"id" => qid}, acc when is_binary(qid) ->
          {:cont, Map.put(acc, qid, %{"answers" => [non_interactive_answer]})}

        _, _ ->
          {:halt, :error}
      end)

    case result do
      :error -> :error
      map when map_size(map) > 0 -> {:ok, map}
      _ -> :error
    end
  end

  def build_non_interactive_answers(_, _), do: :error

  def input_required?(params) when is_map(params) do
    Map.get(params, "requiresInput") == true or
      Map.get(params, "needsInput") == true or
      Map.get(params, "input_required") == true or
      Map.get(params, "inputRequired") == true
  end

  def input_required?(_), do: false

  defp log_non_json(log_prefix, line) do
    trimmed = String.trim(line)

    if trimmed != "" do
      message = "#{log_prefix} non-JSON: #{String.slice(trimmed, 0, 200)}"

      if String.match?(trimmed, @error_like) do
        Logger.warning(message)
      else
        Logger.debug(message)
      end
    end
  end

  defp normalize_utf8(line) when is_binary(line) do
    case String.valid?(line) do
      true -> line
      false -> :unicode.characters_to_binary(line, :latin1, :utf8)
    end
  end
end
