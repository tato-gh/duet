defmodule Duet.AIClient do
  @moduledoc """
  管理リソースはAI app-serverとの接続、入出力
  """

  use GenServer
  require Logger

  @topic "duet:events"
  @debug Mix.env() == :dev

  @port_line_bytes 1_048_576

  # state:
  #   port:            app-server の OS プロセスポート
  #   cwd:             DUETFLOW.md があるディレクトリ
  #   thread_id:       thread/start レスポンスで得た UUID（nil = セッション未確立）
  #   status:          :starting | :initializing | :session_ready | :idle | :waiting
  #   rpc_id:          次に使う JSON-RPC id
  #   pending_method:  直前に送ったリクエストの種別（:initialize | :thread_start | :turn_start | nil）
  #                    レスポンスの id ではなく pending_method で分岐することで rpc_id 管理を不要にする
  #   pending_delta:   次のポーリング後に送るべき diff（nil = なし。最新のみ保持）
  #   pending_reset:   true なら turn 完了後に thread/start でコンテキストリセット
  #   prompt:          現在の DUETFLOW.md プロンプト本文
  #   first_turn:      true なら次の turn/start に prompt を付与（thread/start 直後にリセット）
  #   buf:             line モードで noeol チャンクを蓄積するバッファ

  # --- Public API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Duet.PubSub, @topic)
    command = Duet.Poller.get_command()
    cwd = Duet.Duetflow.duetflow_file_path() |> Path.dirname()
    port = start_app_server(command, cwd)

    state = %{
      port: port,
      cwd: cwd,
      thread_id: nil,
      status: :starting,
      rpc_id: 1,
      pending_method: nil,
      pending_delta: nil,
      pending_reset: false,
      prompt: nil,
      first_turn: true,
      buf: ""
    }

    send(self(), :do_initialize)
    {:ok, state}
  end

  # 初期化シーケンス: initialize リクエスト送信
  @impl true
  def handle_info(:do_initialize, state) do
    state =
      send_rpc(state, "initialize", %{
        capabilities: %{experimentalApi: true},
        clientInfo: %{name: "duet", title: "Duet", version: "0.1.0"}
      })

    {:noreply, %{state | status: :initializing, pending_method: :initialize}}
  end

  # app-server からのデータ受信（line モード: 1行確定）
  @impl true
  def handle_info({port, {:data, {:eol, chunk}}}, %{port: port} = state) do
    line = state.buf <> chunk
    state = decode_and_process(line, %{state | buf: ""})
    {:noreply, state}
  end

  # app-server からのデータ受信（line モード: 行の途中）
  @impl true
  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    {:noreply, %{state | buf: state.buf <> chunk}}
  end

  # app-server プロセス異常終了
  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.error("app-server exited with status #{status}")
    {:stop, {:port_exit, status}, state}
  end

  # PubSub: diff 変化（non-empty → non-empty）
  @impl true
  def handle_info({:diff_changed, %{diff: delta}}, state) do
    {:noreply, %{state | pending_delta: delta} |> maybe_flush()}
  end

  # PubSub: diff 開始（empty → non-empty）
  @impl true
  def handle_info({:diff_started, %{prompt: prompt, diff: diff}}, state) do
    {:noreply, %{state | prompt: prompt, pending_delta: diff} |> maybe_flush()}
  end

  # PubSub: diff が空になった → thread/start で会話スレッドをリセット
  @impl true
  def handle_info({:context_reset, %{prompt: prompt}}, state) do
    {:noreply, %{state | prompt: prompt, pending_delta: nil, pending_reset: true} |> maybe_flush()}
  end

  # PubSub: DUETFLOW.md の prompt 本文が変わった → コンテキストリセット
  @impl true
  def handle_info({:prompt_changed, %{prompt: new_prompt}}, state) do
    {:noreply, %{state | prompt: new_prompt, pending_delta: nil, pending_reset: true} |> maybe_flush()}
  end

  # PubSub: command 等の設定が変わった → Supervisor に再起動させる
  @impl true
  def handle_info({:config_changed, _payload}, state) do
    {:stop, :config_changed, state}
  end

  # --- Private: JSON デコードと処理 ---

  defp decode_and_process(line, state) do
    try do
      msg = JSON.decode!(line)
      process_message(msg, state)
    rescue
      _ ->
        trimmed = String.trim(line)
        if trimmed != "" do
          Logger.debug("[AIClient] non-JSON: #{String.slice(trimmed, 0, 200)}")
        end

        state
    end
  end

  # --- Private: JSON-RPC 送受信 ---

  defp send_rpc(state, method, params) do
    msg = %{method: method, id: state.rpc_id, params: params}
    if @debug, do: Logger.debug("[AIClient] → RPC id=#{state.rpc_id} method=#{method} params=#{inspect(params)}")
    Port.command(state.port, JSON.encode!(msg) <> "\n")
    %{state | rpc_id: state.rpc_id + 1}
  end

  defp send_notification(state, method, params) do
    msg = %{method: method, params: params}
    if @debug, do: Logger.debug("[AIClient] → notification method=#{method} params=#{inspect(params)}")
    Port.command(state.port, JSON.encode!(msg) <> "\n")
    state
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
    state = send_notification(state, "initialized", %{})

    state =
      send_rpc(state, "thread/start", %{
        approvalPolicy: "never",
        sandbox: "readOnly",
        cwd: state.cwd
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

  defp handle_notification("turn/completed", _params, state) do
    state = %{state | status: :idle, pending_method: nil}
    flush_pending(state)
  end

  defp handle_notification(method, _params, state)
       when method in ["turn/failed", "turn/cancelled"] do
    Logger.error("Turn #{method}")
    state = %{state | status: :idle, pending_method: nil}
    flush_pending(state)
  end

  defp handle_notification("item/completed", params, state) do
    with "agentMessage" <- get_in(params, ["item", "type"]),
         text when is_binary(text) <- get_in(params, ["item", "text"]) do
      IO.puts(text)
    end

    state
  end

  defp handle_notification("item/commandExecution/requestApproval", params, state) do
    send_response(state, params["id"], %{decision: "acceptForSession"})
    state
  end

  defp handle_notification("item/fileChange/requestApproval", params, state) do
    send_response(state, params["id"], %{decision: "reject"})
    state
  end

  defp handle_notification(_method, _params, state), do: state

  defp flush_pending(%{pending_reset: true} = state) do
    state =
      send_rpc(state, "thread/start", %{
        approvalPolicy: "never",
        sandbox: "readOnly",
        cwd: state.cwd
      })

    %{state | pending_reset: false, status: :session_ready, pending_method: :thread_start}
  end

  defp flush_pending(%{pending_delta: delta} = state) when not is_nil(delta) do
    input = build_turn_input(state)

    state =
      send_rpc(state, "turn/start", %{
        threadId: state.thread_id,
        input: input,
        cwd: state.cwd,
        approvalPolicy: "never"
      })

    %{state | pending_delta: nil, status: :waiting, pending_method: :turn_start, first_turn: false}
  end

  defp flush_pending(state), do: %{state | status: :idle}

  # 初回ターンのみ prompt を先頭に付与する
  defp build_turn_input(%{first_turn: true, prompt: prompt, pending_delta: delta})
       when is_binary(prompt) do
    [%{type: "text", text: prompt <> "\n\n" <> delta}]
  end

  defp build_turn_input(%{pending_delta: delta}) do
    [%{type: "text", text: delta}]
  end

  defp send_response(state, id, result) do
    Port.command(state.port, JSON.encode!(%{id: id, result: result}) <> "\n")
  end

  defp maybe_flush(%{status: :idle} = state), do: flush_pending(state)
  defp maybe_flush(state), do: state

  defp start_app_server(command, cwd) do
    bash = System.find_executable("bash") || raise "bash not found in PATH"

    Port.open(
      {:spawn_executable, String.to_charlist(bash)},
      [
        :binary,
        :exit_status,
        args: [~c"-lc", String.to_charlist(command)],
        cd: String.to_charlist(cwd),
        line: @port_line_bytes
      ]
    )
  end
end
