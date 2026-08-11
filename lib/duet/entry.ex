defmodule Duet.Entry do
  @moduledoc false

  use GenServer
  require Logger
  alias Duet.AppServerCommon

  @port_line_bytes 1_048_576
  @non_interactive_answer "This is a non-interactive session. Operator input is unavailable."
  @timeout_avoidance_practice """
  もし完了の見通しが立たないリクエストを受けた場合は、まず全体像を把握し、ステップに分割した計画を提示したうえで、「1ステップずつ進めましょう」と相手に伝えてください。これはタイムアウト防止のためのプラクティスです。
  """

  def start_link(%{name: name} = config) do
    GenServer.start_link(__MODULE__, config, name: {:via, Registry, {Duet.EntryRegistry, name}})
  end

  def child_spec(%{name: name} = config) do
    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [config]},
      restart: :permanent,
      type: :worker
    }
  end

  @impl true
  def init(
        %{
          name: name,
          command: command,
          role: role,
          approval_policy: approval_policy,
          thread_sandbox: thread_sandbox,
          turn_sandbox_policy: turn_sandbox_policy
        } = config
      ) do
    model = Map.get(config, :model)
    reasoning_effort = Map.get(config, :reasoning_effort)
    service_tier = Map.get(config, :service_tier)
    cwd = Duet.Config.config_file_path() |> Path.dirname()
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
      model: model,
      reasoning_effort: reasoning_effort,
      service_tier: service_tier,
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

  @impl true
  def handle_call({:post, _prompt}, _from, %{status: status} = state) when status != :idle do
    {:reply, {:error, :busy}, state}
  end

  @impl true
  def handle_call({:post, "/clear"}, from, state) do
    state =
      AppServerCommon.send_rpc(state, "thread/start", thread_start_params(state))

    {:noreply,
     %{state | status: :session_ready, pending_method: :thread_start, pending_call: from}}
  end

  @impl true
  def handle_call({:post, "/compact"}, from, state) do
    state =
      AppServerCommon.send_rpc(
        state,
        "turn/start",
        turn_start_params(state, [%{type: "text", text: build_compact_summary_prompt()}])
      )

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
      AppServerCommon.send_rpc(state, "turn/start", turn_start_params(state, input))

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
    Logger.error("[Duet.Entry:#{state.name}] app-server exited with status #{status}")
    {:stop, {:port_exit, status}, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp decode_and_process(line, state) do
    AppServerCommon.decode_and_process(
      line,
      state,
      &process_message/2,
      "[Duet.Entry:#{state.name}]"
    )
  end

  defp process_message(%{"result" => result} = msg, state) do
    handle_response(msg["id"], result, state)
  end

  defp process_message(%{"error" => error} = msg, state) do
    Logger.error("[Duet.Entry:#{state.name}] RPC error for id=#{msg["id"]}: #{inspect(error)}")
    handle_rpc_error(error, state)
  end

  defp process_message(%{"method" => method} = msg, state) do
    handle_notification(method, msg["params"] || %{}, state)
  end

  defp process_message(_msg, state), do: state

  defp handle_response(_id, _result, %{pending_method: :initialize} = state) do
    state = AppServerCommon.send_notification(state, "initialized", %{})

    state =
      AppServerCommon.send_rpc(state, "thread/start", thread_start_params(state))

    %{state | status: :session_ready, pending_method: :thread_start}
  end

  defp handle_response(
         _id,
         result,
         %{pending_method: :thread_start, pending_compact_summary: summary} = state
       )
       when is_binary(summary) and summary != "" do
    thread_id = get_in(result, ["thread", "id"])
    Logger.info("[Duet.Entry:#{state.name}] /compact: new thread #{thread_id} established")

    state_with_new_thread = %{state | thread_id: thread_id, first_turn: true}
    input = build_turn_input(state_with_new_thread, build_compact_handoff_prompt(summary))

    state =
      AppServerCommon.send_rpc(
        state_with_new_thread,
        "turn/start",
        turn_start_params(state_with_new_thread, input)
      )

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

  defp handle_rpc_error(error, %{pending_method: :initialize}) do
    raise "app-server initialize failed: #{inspect(error)}"
  end

  defp handle_rpc_error(error, state) do
    if state.pending_call do
      GenServer.reply(state.pending_call, {:error, {:rpc_error, error}})
    end

    %{
      state
      | status: :idle,
        pending_method: nil,
        pending_call: nil,
        pending_compact_summary: nil,
        response_buf: ""
    }
  end

  defp handle_notification("turn/completed", params, %{status: :compacting_summary} = state) do
    case get_in(params, ["turn", "status"]) do
      status when status in ["failed", "interrupted"] ->
        Logger.error(
          "[Duet.Entry:#{state.name}] compact summary turn ended with status: #{status}"
        )

        if state.pending_call do
          GenServer.reply(state.pending_call, {:error, status})
        end

        %{state | status: :idle, pending_method: nil, pending_call: nil, response_buf: ""}

      _ ->
        summary = String.trim(state.response_buf)

        if summary == "" do
          Logger.error("[Duet.Entry:#{state.name}] /compact: summary was empty")

          if state.pending_call do
            GenServer.reply(state.pending_call, {:error, :empty_compact_summary})
          end

          %{state | status: :idle, pending_method: nil, pending_call: nil, response_buf: ""}
        else
          Logger.info("[Duet.Entry:#{state.name}] /compact: summary captured")

          state =
            AppServerCommon.send_rpc(state, "thread/start", thread_start_params(state))

          %{
            state
            | status: :session_ready,
              pending_method: :thread_start,
              pending_compact_summary: summary,
              response_buf: ""
          }
        end
    end
  end

  defp handle_notification("turn/completed", params, state) do
    case get_in(params, ["turn", "status"]) do
      status when status in ["failed", "interrupted"] ->
        Logger.error("[Duet.Entry:#{state.name}] turn ended with status: #{status}")

        if state.pending_call do
          GenServer.reply(state.pending_call, {:error, status})
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
    %{state | response_buf: state.response_buf <> (params["delta"] || "")}
  end

  defp handle_notification("item/completed", _params, state), do: state

  defp handle_notification("item/commandExecution/requestApproval", params, state) do
    AppServerCommon.send_response(state, params["id"], %{decision: "reject"})
    state
  end

  defp handle_notification("execCommandApproval", params, state) do
    AppServerCommon.send_response(state, params["id"], %{decision: "denied"})
    state
  end

  defp handle_notification("applyPatchApproval", params, state) do
    AppServerCommon.send_response(state, params["id"], %{decision: "denied"})
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
        Logger.warning("[Duet.Entry:#{state.name}] requestUserInput: cannot build answers")
    end

    state
  end

  defp handle_notification("turn/failed", params, state) do
    Logger.error("[Duet.Entry:#{state.name}] turn/failed: #{inspect(params)}")

    if state.pending_call do
      GenServer.reply(state.pending_call, {:error, :turn_failed})
    end

    %{state | status: :idle, pending_method: nil, pending_call: nil, response_buf: ""}
  end

  defp handle_notification("turn/cancelled", params, state) do
    Logger.warning("[Duet.Entry:#{state.name}] turn/cancelled: #{inspect(params)}")

    if state.pending_call do
      GenServer.reply(state.pending_call, {:error, :turn_cancelled})
    end

    %{state | status: :idle, pending_method: nil, pending_call: nil, response_buf: ""}
  end

  defp handle_notification(_method, _params, state), do: state

  defp thread_start_params(state) do
    %{
      approvalPolicy: state.approval_policy,
      sandbox: state.thread_sandbox,
      cwd: state.cwd,
      dynamicTools: []
    }
    |> maybe_put(:model, state.model)
    |> maybe_put(:serviceTier, state.service_tier)
  end

  defp turn_start_params(state, input) do
    %{
      threadId: state.thread_id,
      input: input,
      cwd: state.cwd,
      approvalPolicy: state.approval_policy,
      sandboxPolicy: state.turn_sandbox_policy
    }
    |> maybe_put(:effort, state.reasoning_effort)
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: Map.put(params, key, value)

  defp build_compact_summary_prompt do
    """
    現在の会話を新しいスレッドへ引き継ぐため、後続のAIエージェント向けの引き継ぎメモを作成してください。

    含める内容:
    - ユーザーの目的、制約、明示された好み
    - 決定済みの方針と、その理由
    - 作業の現状、変更済みのファイル、確認済みの事実
    - 未解決の課題、次に行うべきこと、注意点
    - 重要なコード、コマンド、エラー、参照情報

    憶測は事実と分けてください。不要な挨拶や前置きは避けてください。
    要約のみを出力し、それ以外のコメントは不要です。
    """
    |> String.trim()
  end

  defp build_compact_handoff_prompt(summary) do
    """
    以下は前スレッドからの引き継ぎ情報です。
    これはユーザーからの新しい作業依頼ではなく、今後の応答で保持すべき会話文脈です。
    内容を把握したうえで、以後この前提を引き継いでください。

    <handoff>
    #{summary}
    </handoff>

    引き継ぎ内容を短く確認してください。
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
