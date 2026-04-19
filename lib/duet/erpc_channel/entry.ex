defmodule Duet.ErpcChannel.Entry do
  @moduledoc """
  管理リソースは erpc_channel エントリ単位の AI app-server 接続・入出力
  """

  use GenServer
  require Logger
  alias Duet.AppServerCommon

  @port_line_bytes 1_048_576
  @non_interactive_answer "This is a non-interactive session. Operator input is unavailable."
  @timeout_avoidance_practice """
  もし完了の見通しが立たないリクエストを受けた場合は、まず全体像を把握し、ステップに分割した計画を提示したうえで、「1ステップずつ進めましょう」と相手に伝えてください。これはタイムアウト防止のためのプラクティスです。
  """

  # state:
  #   name:                    エントリ名（atom or string）
  #   port:                    app-server の OS プロセスポート
  #   cwd:                     DUETFLOW.md があるディレクトリ
  #   thread_id:               nil = セッション未確立
  #   status:                  :starting | :initializing | :session_ready | :idle | :waiting | :compacting_summary
  #   rpc_id:                  次に使う JSON-RPC id
  #   pending_method:          直前に送ったリクエストの種別
  #   role:                    エントリの役割（初回ターンのみ付与。空文字なら付与しない）
  #   first_turn:              true なら次の turn/start に role を付与
  #   buf:                     line モードで noeol チャンクを蓄積するバッファ
  #   response_buf:            LLM レスポンスを蓄積するバッファ
  #   pending_call:            {from} — post/2 の呼び出し元（turn 完了時に reply する）
  #   pending_compact_summary: /compact 時の要約テキスト（thread/start 後の first turn に付与）

  # --- Public API ---

  def start_link(%{name: name} = config) do
    GenServer.start_link(__MODULE__, config,
      name: {:via, Registry, {Duet.ErpcChannel.Registry, name}}
    )
  end

  def child_spec(%{name: name} = config) do
    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [config]},
      restart: :permanent,
      type: :worker
    }
  end

  # --- Callbacks ---

  @impl true
  def init(%{
        name: name,
        command: command,
        role: role,
        approval_policy: approval_policy,
        thread_sandbox: thread_sandbox,
        turn_sandbox_policy: turn_sandbox_policy
      }) do
    cwd = Duet.Duetflow.duetflow_file_path() |> Path.dirname()
    port = AppServerCommon.start_app_server(command, cwd, @port_line_bytes)

    state = %{
      name: name,
      port: port,
      cwd: cwd,
      thread_id: nil,
      status: :starting,
      rpc_id: 1,
      pending_method: nil,
      role: role,
      approval_policy: approval_policy,
      thread_sandbox: thread_sandbox,
      turn_sandbox_policy: turn_sandbox_policy,
      first_turn: true,
      buf: "",
      response_buf: "",
      pending_call: nil,
      pending_compact_summary: nil
    }

    send(self(), :do_initialize)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_role, _from, state) do
    {:reply, state.role, state}
  end

  # erpc クライアントからの post 呼び出し
  @impl true
  def handle_call({:post, _prompt}, _from, %{status: status} = state)
      when status not in [:idle] do
    {:reply, {:error, :busy}, state}
  end

  @impl true
  def handle_call({:post, "/clear"}, from, state) do
    state =
      AppServerCommon.send_rpc(state, "thread/start", %{
        approvalPolicy: state.approval_policy,
        sandbox: state.thread_sandbox,
        cwd: state.cwd,
        dynamicTools: []
      })

    {:noreply,
     %{state | status: :session_ready, pending_method: :thread_start, pending_call: from}}
  end

  @impl true
  def handle_call({:post, "/compact"}, from, state) do
    state =
      AppServerCommon.send_rpc(state, "turn/start", %{
        threadId: state.thread_id,
        input: [%{type: "text", text: build_compact_summary_prompt()}],
        cwd: state.cwd,
        approvalPolicy: state.approval_policy,
        sandboxPolicy: state.turn_sandbox_policy
      })

    {:noreply,
     %{
       state
       | status: :compacting_summary,
         pending_method: :turn_start,
         pending_call: from,
         response_buf: ""
     }}
  end

  @impl true
  def handle_call({:post, prompt}, from, state) do
    input = build_turn_input(state, prompt)

    state =
      AppServerCommon.send_rpc(state, "turn/start", %{
        threadId: state.thread_id,
        input: input,
        cwd: state.cwd,
        approvalPolicy: state.approval_policy,
        sandboxPolicy: state.turn_sandbox_policy
      })

    {:noreply,
     %{
       state
       | status: :waiting,
         pending_method: :turn_start,
         pending_call: from,
         response_buf: ""
     }}
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
    Logger.error("[ErpcChannel.Entry:#{state.name}] app-server exited with status #{status}")
    {:stop, {:port_exit, status}, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private: JSON デコードと処理 ---

  defp decode_and_process(line, state) do
    AppServerCommon.decode_and_process(
      line,
      state,
      &process_message/2,
      "[ErpcChannel.Entry:#{state.name}]"
    )
  end

  defp process_message(%{"result" => result} = msg, state) do
    handle_response(msg["id"], result, state)
  end

  defp process_message(%{"error" => error} = msg, state) do
    Logger.error(
      "[ErpcChannel.Entry:#{state.name}] RPC error for id=#{msg["id"]}: #{inspect(error)}"
    )

    state
  end

  defp process_message(%{"method" => method} = msg, state) do
    handle_notification(method, msg["params"] || %{}, state)
  end

  defp process_message(_msg, state), do: state

  defp handle_response(_id, _result, %{pending_method: :initialize} = state) do
    state = AppServerCommon.send_notification(state, "initialized", %{})

    state =
      AppServerCommon.send_rpc(state, "thread/start", %{
        approvalPolicy: state.approval_policy,
        sandbox: state.thread_sandbox,
        cwd: state.cwd,
        dynamicTools: []
      })

    %{state | status: :session_ready, pending_method: :thread_start}
  end

  defp handle_response(
         _id,
         result,
         %{pending_method: :thread_start, pending_compact_summary: summary} = state
       )
       when is_binary(summary) and summary != "" do
    thread_id = get_in(result, ["thread", "id"])

    Logger.info(
      "[ErpcChannel.Entry:#{state.name}] /compact: new thread #{thread_id} established, sending summary as first turn"
    )

    state_with_new_thread = %{state | thread_id: thread_id, first_turn: true}
    input = build_turn_input(state_with_new_thread, summary)

    state =
      AppServerCommon.send_rpc(state_with_new_thread, "turn/start", %{
        threadId: thread_id,
        input: input,
        cwd: state.cwd,
        approvalPolicy: state.approval_policy,
        sandboxPolicy: state.turn_sandbox_policy
      })

    %{
      state
      | thread_id: thread_id,
        status: :waiting,
        pending_method: :turn_start,
        first_turn: false,
        pending_compact_summary: nil
    }
  end

  defp handle_response(_id, result, %{pending_method: :thread_start} = state) do
    thread_id = get_in(result, ["thread", "id"])
    state = %{state | thread_id: thread_id, status: :idle, pending_method: nil, first_turn: true}

    if state.pending_call do
      GenServer.reply(state.pending_call, {:ok, ""})
      %{state | pending_call: nil}
    else
      state
    end
  end

  defp handle_response(_id, _result, %{pending_method: :turn_start} = state) do
    %{state | pending_method: nil}
  end

  defp handle_response(_id, _result, state), do: state

  defp handle_notification("turn/completed", params, %{status: :compacting_summary} = state) do
    case get_in(params, ["turn", "status"]) do
      s when s in ["failed", "interrupted"] ->
        Logger.error(
          "[ErpcChannel.Entry:#{state.name}] compact summary turn ended with status: #{s}"
        )

        if state.pending_call do
          GenServer.reply(state.pending_call, {:error, s})
        end

        %{state | status: :idle, pending_method: nil, pending_call: nil, response_buf: ""}

      _ ->
        summary = String.trim(state.response_buf)

        Logger.info(
          "[ErpcChannel.Entry:#{state.name}] /compact: summary captured (#{String.length(summary)} chars), sending thread/start"
        )

        state =
          AppServerCommon.send_rpc(state, "thread/start", %{
            approvalPolicy: state.approval_policy,
            sandbox: state.thread_sandbox,
            cwd: state.cwd,
            dynamicTools: []
          })

        %{
          state
          | status: :session_ready,
            pending_method: :thread_start,
            pending_compact_summary: summary,
            response_buf: ""
        }
    end
  end

  defp handle_notification("turn/completed", params, state) do
    case get_in(params, ["turn", "status"]) do
      s when s in ["failed", "interrupted"] ->
        Logger.error("[ErpcChannel.Entry:#{state.name}] turn ended with status: #{s}")

        if state.pending_call do
          GenServer.reply(state.pending_call, {:error, s})
        end

        %{state | status: :idle, pending_method: nil, pending_call: nil, response_buf: ""}

      _ ->
        response = String.trim(state.response_buf)

        if state.pending_call do
          GenServer.reply(state.pending_call, {:ok, response})
        end

        %{
          state
          | status: :idle,
            pending_method: nil,
            pending_call: nil,
            response_buf: "",
            first_turn: false
        }
    end
  end

  defp handle_notification("item/agentMessage/delta", params, state) do
    delta = params["delta"] || ""
    %{state | response_buf: state.response_buf <> delta}
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
    AppServerCommon.send_response(state, params["id"], %{decision: "reject"})
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
          "[ErpcChannel.Entry:#{state.name}] requestUserInput: cannot build answers, ignoring"
        )
    end

    state
  end

  defp handle_notification("turn/failed", params, state) do
    Logger.error("[ErpcChannel.Entry:#{state.name}] turn/failed: #{inspect(params)}")

    if state.pending_call do
      GenServer.reply(state.pending_call, {:error, :turn_failed})
    end

    %{state | status: :idle, pending_method: nil, pending_call: nil, response_buf: ""}
  end

  defp handle_notification("turn/cancelled", params, state) do
    Logger.warning("[ErpcChannel.Entry:#{state.name}] turn/cancelled: #{inspect(params)}")

    if state.pending_call do
      GenServer.reply(state.pending_call, {:error, :turn_cancelled})
    end

    %{state | status: :idle, pending_method: nil, pending_call: nil, response_buf: ""}
  end

  defp handle_notification(_method, _params, state), do: state

  # --- Private: Helpers ---

  defp build_compact_summary_prompt do
    """
    別のLLMインスタンスに引き継ぎます。引き継ぎ文章を出力してください。
    決定事項、作業の現状、未解決の課題、重要なコードや情報を含めてください。
    要約のみを出力し、それ以外のコメントは不要です。
    """
    |> String.trim()
  end

  defp build_turn_input(%{first_turn: true, role: role}, user_prompt) when role != "" do
    role_prompt = String.trim(role)
    practice = String.trim(@timeout_avoidance_practice)

    [
      %{
        type: "text",
        text: "あなたのroleは#{role_prompt}です。\n\n#{practice}\n\n#{user_prompt}"
      }
    ]
  end

  defp build_turn_input(_state, user_prompt) do
    [%{type: "text", text: user_prompt}]
  end
end
