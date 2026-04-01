defmodule Duet.DiffWatch.Runner do
  @moduledoc """
  管理リソースは AI app-server との接続・入出力（diff_watch モード）
  """

  use GenServer
  require Logger
  alias Duet.AppServerCommon

  @topic "duet:events"
  @port_line_bytes 1_048_576
  @non_interactive_answer "This is a non-interactive session. Operator input is unavailable."

  # state:
  #   port:                 app-server の OS プロセスポート
  #   cwd:                  DUETFLOW.md があるディレクトリ
  #   thread_id:            thread/start レスポンスで得た UUID（nil = セッション未確立）
  #   status:               :starting | :initializing | :session_ready | :idle | :waiting
  #   rpc_id:               次に使う JSON-RPC id
  #   pending_method:       直前に送ったリクエストの種別
  #   pending_delta:        次のポーリング後に送るべき diff（nil = なし）
  #   pending_reset:        true なら turn 完了後に thread/start でコンテキストリセット
  #   pending_user_input:   ユーザーが標準入力から送った直接メッセージ（nil = なし）
  #   prompt:               現在の DUETFLOW.md プロンプト本文
  #   first_turn:           true なら次の turn/start に prompt を付与
  #   file_change_approval: ファイル変更承認ポリシー
  #   buf:                  line モードで noeol チャンクを蓄積するバッファ

  # --- Public API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Duet.PubSub, @topic)
    config = Duet.ConfigWatcher.get_config().diff_watch
    cwd = Duet.Duetflow.duetflow_file_path() |> Path.dirname()
    port = AppServerCommon.start_app_server(config.command, cwd, @port_line_bytes)

    state = %{
      port: port,
      cwd: cwd,
      thread_id: nil,
      status: :starting,
      rpc_id: 1,
      pending_method: nil,
      pending_delta: nil,
      pending_reset: false,
      pending_user_input: nil,
      prompt: nil,
      first_turn: true,
      file_change_approval: config.file_change_approval,
      buf: ""
    }

    send(self(), :do_initialize)
    {:ok, state}
  end

  @impl true
  def handle_info(:do_initialize, state) do
    state =
      AppServerCommon.send_rpc(state, "initialize", %{
        capabilities: %{experimentalApi: true},
        clientInfo: %{name: "duet", title: "Duet", version: "0.1.0"}
      })

    {:noreply, %{state | status: :initializing, pending_method: :initialize}}
  end

  @impl true
  def handle_info({port, {:data, {:eol, chunk}}}, %{port: port} = state) do
    line = state.buf <> chunk
    state = decode_and_process(line, %{state | buf: ""})
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    {:noreply, %{state | buf: state.buf <> chunk}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("app-server exited with status #{status}")
    {:stop, {:port_exit, status}, state}
  end

  @impl true
  def handle_info({:diff_changed, %{diff: delta}}, state) do
    {:noreply, %{state | pending_delta: delta} |> maybe_flush()}
  end

  @impl true
  def handle_info({:diff_started, %{prompt: prompt, diff: diff}}, state) do
    {:noreply, %{state | prompt: prompt, pending_delta: diff} |> maybe_flush()}
  end

  @impl true
  def handle_info({:context_reset, %{prompt: prompt}}, state) do
    {:noreply,
     %{state | prompt: prompt, pending_delta: nil, pending_reset: true} |> maybe_flush()}
  end

  @impl true
  def handle_info({:prompt_changed, %{prompt: new_prompt}}, state) do
    {:noreply,
     %{state | prompt: new_prompt, pending_delta: nil, pending_reset: true} |> maybe_flush()}
  end

  @impl true
  def handle_info({:config_changed, _payload}, state) do
    {:stop, :config_changed, state}
  end

  @impl true
  def handle_info({:user_message, %{text: text}}, state) do
    {:noreply, %{state | pending_user_input: text} |> maybe_flush()}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private: JSON デコードと処理 ---

  defp decode_and_process(line, state) do
    AppServerCommon.decode_and_process(line, state, &process_message/2, "[DiffWatch.Runner]")
  end

  defp process_message(%{"result" => result} = msg, state) do
    handle_response(msg["id"], result, state)
  end

  defp process_message(%{"error" => error} = msg, state) do
    handle_rpc_error(msg["id"], error, state)
  end

  defp process_message(%{"method" => method} = msg, state) do
    handle_notification(method, msg["params"] || %{}, state)
  end

  defp process_message(_msg, state), do: state

  defp handle_response(_id, _result, %{pending_method: :initialize} = state) do
    state = AppServerCommon.send_notification(state, "initialized", %{})

    state =
      AppServerCommon.send_rpc(state, "thread/start", %{
        approvalPolicy: "never",
        sandbox: "read-only",
        cwd: state.cwd,
        dynamicTools: []
      })

    %{state | status: :session_ready, pending_method: :thread_start}
  end

  defp handle_response(_id, result, %{pending_method: :thread_start} = state) do
    thread_id = get_in(result, ["thread", "id"])
    state = %{state | thread_id: thread_id, status: :idle, pending_method: nil, first_turn: true}
    flush_pending(state)
  end

  defp handle_response(_id, _result, %{pending_method: :turn_start} = state) do
    %{state | pending_method: nil}
  end

  defp handle_response(_id, _result, state), do: state

  defp handle_rpc_error(id, error, state) do
    Logger.error("RPC error for id=#{id}: #{inspect(error)}")
    state
  end

  defp handle_notification("turn/completed", params, state) do
    case get_in(params, ["turn", "status"]) do
      s when s in ["failed", "interrupted"] ->
        Logger.error("Turn ended with status: #{s}")

      _ ->
        IO.puts("")
    end

    state = %{state | status: :idle, pending_method: nil}
    flush_pending(state)
  end

  defp handle_notification("item/agentMessage/delta", params, state) do
    IO.write(params["delta"] || "")
    state
  end

  defp handle_notification("item/completed", _params, state), do: state

  defp handle_notification("item/commandExecution/requestApproval", params, state) do
    AppServerCommon.send_response(state, params["id"], %{decision: "acceptForSession"})
    state
  end

  defp handle_notification("execCommandApproval", params, state) do
    AppServerCommon.send_response(state, params["id"], %{decision: "approved_for_session"})
    state
  end

  defp handle_notification("applyPatchApproval", params, state) do
    AppServerCommon.send_response(state, params["id"], %{decision: "approved_for_session"})
    state
  end

  defp handle_notification("item/fileChange/requestApproval", params, state) do
    AppServerCommon.send_response(state, params["id"], %{decision: state.file_change_approval})
    state
  end

  defp handle_notification("item/tool/call", params, state) do
    result = %{
      "success" => false,
      "output" => "Unsupported dynamic tool: #{inspect(params["tool"] || params["name"])}",
      "contentItems" => [%{"type" => "inputText", "text" => "unsupported"}]
    }

    AppServerCommon.send_response(state, params["id"], result)
    state
  end

  defp handle_notification("item/tool/requestUserInput", params, state) do
    case AppServerCommon.build_non_interactive_answers(params, @non_interactive_answer) do
      {:ok, answers} ->
        AppServerCommon.send_response(state, params["id"], %{answers: answers})

      :error ->
        Logger.warning(
          "[DiffWatch.Runner] item/tool/requestUserInput: cannot build answers, ignoring"
        )
    end

    state
  end

  defp handle_notification("turn/failed", params, state) do
    Logger.error("[DiffWatch.Runner] turn/failed: #{inspect(params)}")
    state = %{state | status: :idle, pending_method: nil}
    flush_pending(state)
  end

  defp handle_notification("turn/cancelled", params, state) do
    Logger.warning("[DiffWatch.Runner] turn/cancelled: #{inspect(params)}")
    state = %{state | status: :idle, pending_method: nil}
    flush_pending(state)
  end

  defp handle_notification("turn/" <> _ = method, params, state) do
    if AppServerCommon.input_required?(params) do
      Logger.warning(
        "[DiffWatch.Runner] turn input required (method=#{method}), treating as turn end"
      )

      state = %{state | status: :idle, pending_method: nil}
      flush_pending(state)
    else
      state
    end
  end

  defp handle_notification(_method, _params, state), do: state

  defp flush_pending(%{pending_reset: true} = state) do
    state =
      AppServerCommon.send_rpc(state, "thread/start", %{
        approvalPolicy: "never",
        sandbox: "read-only",
        cwd: state.cwd,
        dynamicTools: []
      })

    %{state | pending_reset: false, status: :session_ready, pending_method: :thread_start}
  end

  defp flush_pending(%{pending_user_input: text} = state) when not is_nil(text) do
    IO.puts("\n---\n")

    state =
      AppServerCommon.send_rpc(state, "turn/start", %{
        threadId: state.thread_id,
        input: [%{type: "text", text: text}],
        cwd: state.cwd,
        approvalPolicy: "never"
      })

    %{state | pending_user_input: nil, status: :waiting, pending_method: :turn_start}
  end

  defp flush_pending(%{pending_delta: delta} = state) when not is_nil(delta) do
    IO.puts("\n---\n")

    state =
      AppServerCommon.send_rpc(state, "turn/start", %{
        threadId: state.thread_id,
        input: build_turn_input(state),
        cwd: state.cwd,
        approvalPolicy: "never"
      })

    %{
      state
      | pending_delta: nil,
        status: :waiting,
        pending_method: :turn_start,
        first_turn: false
    }
  end

  defp flush_pending(state), do: %{state | status: :idle}

  @meta_prompt "You are a partner to the user. The user sends messages to you via git diff output as the communication medium. Just respond directly and naturally — no need to treat this as a file editing task."

  defp build_turn_input(%{first_turn: true, prompt: prompt, pending_delta: delta}) do
    header =
      if is_binary(prompt) and prompt != "" do
        @meta_prompt <> "\n\n" <> prompt
      else
        @meta_prompt
      end

    [%{type: "text", text: header <> "\n\n" <> delta}]
  end

  defp build_turn_input(%{pending_delta: delta}) do
    [%{type: "text", text: delta}]
  end

  defp maybe_flush(%{status: :idle} = state), do: flush_pending(state)
  defp maybe_flush(state), do: state
end
