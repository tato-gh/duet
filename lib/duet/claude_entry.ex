defmodule Duet.ClaudeEntry do
  @moduledoc false
  use GenServer
  require Logger

  alias Duet.AppServerCommon
  import Duet.EntryPrompts

  @line_bytes 1_048_576
  @initialize_timeout 60_000

  def start_link(%{name: name} = config) do
    GenServer.start_link(__MODULE__, config, name: {:via, Registry, {Duet.EntryRegistry, name}})
  end

  @impl true
  def init(config) do
    Registry.put_meta(Duet.EntryRegistry, {:entry_failure, config.name}, %{
      status: :unavailable,
      reason: nil
    })

    if config.permission_mode == "default" do
      Logger.warning(
        "[Duet.ClaudeEntry:#{config.name}] Duet cannot forward approval prompts to an operator; " <>
          "requests requiring approval will be denied. Configure tools and allowed_tools " <>
          "for non-interactive use."
      )
    end

    state = %{
      name: config.name,
      role: config.role,
      command: command(config),
      cwd: Duet.Config.config_file_path() |> Path.dirname(),
      port: nil,
      buf: "",
      status: :starting,
      session_id: "",
      session_state: nil,
      first_turn: true,
      pending_call: nil,
      pending_posts: :queue.new(),
      pending_summary: nil,
      control_id: nil,
      interrupt_id: nil,
      interrupt_call: nil,
      interrupted: false,
      completed_result: nil,
      initialize_timer: nil
    }

    {:ok, open_session(state)}
  end

  # Keep protocol flags under Duet's control even for a custom executable/wrapper.
  def command(config) do
    args = [
      "-p",
      "--input-format",
      "stream-json",
      "--output-format",
      "stream-json",
      "--verbose",
      "--permission-prompt-tool",
      "stdio",
      "--permission-mode",
      config.permission_mode,
      "--tools",
      Enum.join(config.tools, ",")
    ]

    args = if config.model, do: args ++ ["--model", config.model], else: args

    args =
      if config.reasoning_effort, do: args ++ ["--effort", config.reasoning_effort], else: args

    args =
      if config.allowed_tools == [],
        do: args,
        else: args ++ ["--allowedTools", Enum.join(config.allowed_tools, ",")]

    config.command <> " " <> Enum.map_join(args, " ", &AppServerCommon.shell_escape/1)
  end

  @impl true
  def handle_call(:get_role, _from, state), do: {:reply, state.role, state}

  def handle_call(:get_status, _from, state),
    do: {:reply, Duet.entry_status(state, :claude), state}

  def handle_call({:post, "/clear"}, from, %{status: :interrupt_unknown} = state),
    do: {:noreply, start_post(state, "/clear", from)}

  def handle_call({:post, _prompt}, _from, %{status: :interrupt_unknown} = state),
    do: {:reply, {:error, :interrupt_timeout}, state}

  def handle_call({:post, prompt}, from, %{status: :idle} = state),
    do: {:noreply, start_post(state, prompt, from)}

  def handle_call({:post, _prompt}, _from, state), do: {:reply, {:error, :busy}, state}

  def handle_call({:enqueue, prompt}, _from, state),
    do: {:reply, :ok, enqueue(state, prompt)}

  def handle_call(:interrupt, _from, %{status: :idle} = state),
    do: {:reply, {:error, :not_running}, state}

  def handle_call(:interrupt, _from, %{interrupted: true} = state),
    do: {:reply, {:error, :interrupting}, state}

  def handle_call(:interrupt, from, %{status: status} = state)
      when status in [:waiting, :compacting_summary] do
    id = send_control(state, %{subtype: "interrupt"})
    Process.send_after(self(), {:interrupt_timeout, id}, 4_000)
    {:noreply, %{state | interrupt_id: id, interrupt_call: from, interrupted: true}}
  end

  def handle_call(:interrupt, _from, state),
    do: {:reply, {:error, :not_interruptible}, state}

  @impl true
  def handle_cast({:enqueue, prompt}, state), do: {:noreply, enqueue(state, prompt)}

  @impl true
  def handle_info({port, {:data, {:eol, chunk}}}, %{port: port} = state) do
    next =
      AppServerCommon.decode_and_process(
        state.buf <> chunk,
        %{state | buf: ""},
        &process_message/2,
        "[Duet.ClaudeEntry:#{state.name}]"
      )

    {:noreply, next}
  end

  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state),
    do: {:noreply, %{state | buf: state.buf <> chunk}}

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    reply(state.pending_call, {:error, {:port_exit, status}})
    reply(state.interrupt_call, {:error, {:port_exit, status}})

    reason =
      if state.status == :initializing,
        do: startup_failure(state, {:port_exit, status}),
        else: {:port_exit, status}

    {:stop, reason, %{state | pending_call: nil, interrupt_call: nil}}
  end

  def handle_info({:initialize_timeout, id}, %{control_id: id} = state) do
    reply(state.pending_call, {:error, :initialize_timeout})
    {:stop, startup_failure(state, :initialize_timeout), %{state | pending_call: nil}}
  end

  def handle_info({:interrupt_timeout, id}, %{interrupt_id: id} = state) do
    reply(state.interrupt_call, {:error, :interrupt_timeout})
    reply(state.pending_call, {:error, :interrupt_timeout})
    # Retain the request ID: a delayed acknowledgement must still be consumed
    # before a queued prompt is sent. /clear explicitly abandons this session
    # when the peer never acknowledges; a timeout is not a confirmed interrupt.
    {:noreply, %{state | status: :interrupt_unknown, interrupt_call: nil, pending_call: nil}}
  end

  # Includes messages from a Port retired by /clear or /compact.
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    if reason not in [:normal, :shutdown], do: Duet.record_entry_failure(state.name, reason)
    close_port(state.port)
  end

  defp open_session(state) do
    # Like the Agent SDK, allow a host launched from Claude Code to start an
    # independent session instead of inheriting the interactive nesting marker.
    port =
      AppServerCommon.start_app_server(state.command, state.cwd, @line_bytes, state.name, [
        {~c"CLAUDECODE", false},
        {~c"CLAUDE_CODE_SDK_READS_SESSION_STATE", ~c"1"}
      ])

    state = %{
      state
      | port: port,
        buf: "",
        status: :initializing,
        session_id: "",
        session_state: nil,
        first_turn: true,
        interrupted: false,
        interrupt_id: nil,
        interrupt_call: nil,
        completed_result: nil
    }

    id = send_control(state, %{subtype: "initialize", hooks: nil})
    timer = Process.send_after(self(), {:initialize_timeout, id}, @initialize_timeout)
    %{state | control_id: id, initialize_timer: timer}
  end

  defp process_message(%{"type" => "control_response", "response" => response}, state) do
    case response["request_id"] do
      id when id == state.control_id and not is_nil(id) ->
        Process.cancel_timer(state.initialize_timer)

        if response["subtype"] == "success" do
          state = %{state | status: :idle, control_id: nil, initialize_timer: nil}

          case state.pending_summary do
            nil ->
              Logger.info("[Duet.ClaudeEntry:#{state.name}] ready (claude)")
              complete_post(state, {:ok, ""})

            summary ->
              start_post(
                %{state | pending_summary: nil},
                build_compact_handoff_prompt(summary),
                state.pending_call
              )
          end
        else
          # Immediate retries of a broken CLI/configuration can exhaust the
          # shared supervisor's restart budget and stop healthy entries too.
          reply(state.pending_call, {:error, {:initialize_failed, response["error"]}})
          exit(startup_failure(state, {:initialize_failed, response["error"]}))
        end

      id when id == state.interrupt_id and not is_nil(id) ->
        success = response["subtype"] == "success"
        result = if success, do: :ok, else: {:error, {:control_error, response["error"]}}
        reply(state.interrupt_call, result)
        release_result(%{state | interrupt_call: nil, interrupt_id: nil, interrupted: success})

      _ ->
        state
    end
  end

  defp process_message(
         %{"type" => "control_request", "request_id" => id, "request" => request},
         state
       ) do
    response =
      if request["subtype"] == "can_use_tool" do
        %{
          subtype: "success",
          request_id: id,
          response: %{
            behavior: "deny",
            message: "Duet is non-interactive; operator input is unavailable."
          }
        }
      else
        %{subtype: "error", request_id: id, error: "Unsupported control request"}
      end

    send_message(state, %{type: "control_response", response: response})
    state
  end

  defp process_message(%{"type" => "system", "subtype" => "init", "session_id" => id}, state),
    do: %{state | session_id: id}

  defp process_message(
         %{"type" => "system", "subtype" => "session_state_changed", "state" => session_state},
         state
       )
       when session_state in ["running", "requires_action", "idle"] do
    release_result(%{state | session_state: session_state})
  end

  defp process_message(%{"type" => type} = message, state)
       when type in ["assistant", "stream_event"] do
    if is_nil(message["parent_tool_use_id"]) and not is_nil(state.session_state) do
      # A background task can wake the main conversation for another turn.
      # Its predecessor's result must not complete this new turn on early idle.
      %{state | completed_result: nil}
    else
      state
    end
  end

  defp process_message(%{"type" => "result"} = message, %{status: status} = state)
       when status in [:waiting, :compacting_summary, :interrupt_unknown] do
    # A result may precede the interrupt acknowledgement. Hold the queue until
    # both have arrived, so a late interrupt cannot cancel the next prompt.
    release_result(%{state | completed_result: message})
  end

  defp process_message(_message, state), do: state

  defp release_result(%{completed_result: nil} = state), do: state
  defp release_result(%{interrupt_id: id} = state) when not is_nil(id), do: state

  defp release_result(%{session_state: phase} = state)
       when phase in ["running", "requires_action"], do: state

  defp release_result(state) do
    message = state.completed_result
    state = %{state | completed_result: nil}

    cond do
      state.interrupted ->
        finish(state, {:error, "interrupted"})

      message["is_error"] == true or message["subtype"] != "success" ->
        finish(
          state,
          {:error, {:claude_error, error_reason(message)}}
        )

      state.status == :compacting_summary ->
        summary = String.trim(message["result"] || "")

        if summary == "" do
          finish(state, {:error, :empty_compact_summary})
        else
          close_port(state.port)
          open_session(%{state | pending_summary: summary})
        end

      true ->
        finish(state, {:ok, String.trim(message["result"] || "")})
    end
  end

  defp start_post(state, "/clear", from) do
    close_port(state.port)
    open_session(%{state | pending_call: from})
  end

  defp start_post(state, "/compact", from) do
    send_prompt(state, build_compact_summary_prompt())

    %{
      state
      | status: :compacting_summary,
        pending_call: from,
        session_state: next_session_state(state)
    }
  end

  defp start_post(state, prompt, from) do
    [%{text: text}] = build_turn_input(state, prompt)
    send_prompt(state, text)

    %{
      state
      | status: :waiting,
        pending_call: from,
        first_turn: false,
        session_state: next_session_state(state)
    }
  end

  # Older CLIs do not emit state events; retain result-only completion for them.
  defp next_session_state(%{session_state: nil}), do: nil
  defp next_session_state(_state), do: "running"

  defp error_reason(message) do
    case message["errors"] do
      [_ | _] = errors ->
        errors

      _ ->
        case message["result"] do
          text when is_binary(text) and text != "" -> text
          _ -> message["subtype"] || "unknown error"
        end
    end
  end

  defp startup_failure(state, reason) do
    Logger.error("[Duet.ClaudeEntry:#{state.name}] startup failed: #{inspect(reason)}")
    {:shutdown, reason}
  end

  defp send_prompt(state, text) do
    send_message(state, %{
      type: "user",
      session_id: state.session_id,
      message: %{role: "user", content: text},
      parent_tool_use_id: nil
    })
  end

  defp finish(state, result) do
    complete_post(%{state | status: :idle, interrupted: false}, result)
  end

  defp complete_post(state, result) do
    reply(state.pending_call, result)
    state = %{state | pending_call: nil}

    case :queue.out(state.pending_posts) do
      {{:value, prompt}, rest} -> start_post(%{state | pending_posts: rest}, prompt, nil)
      {:empty, _} -> state
    end
  end

  defp enqueue(%{status: :idle} = state, prompt), do: start_post(state, prompt, nil)

  defp enqueue(state, prompt),
    do: %{state | pending_posts: :queue.in(prompt, state.pending_posts)}

  defp send_control(state, request) do
    id = "duet-#{System.unique_integer([:positive, :monotonic])}"
    send_message(state, %{type: "control_request", request_id: id, request: request})
    id
  end

  defp send_message(state, message), do: Port.command(state.port, JSON.encode!(message) <> "\n")
  defp reply(nil, _result), do: :ok
  defp reply(from, result), do: GenServer.reply(from, result)

  defp close_port(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  end
end
