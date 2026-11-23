defmodule Duet.AgyEntry do
  @moduledoc false

  use GenServer
  require Logger

  alias Duet.AppServerCommon
  import Duet.EntryPrompts

  @initialize_timeout 60_000
  @interrupt_timeout 4_000
  @line_bytes 1_048_576

  def start_link(%{name: name} = config) do
    GenServer.start_link(__MODULE__, config, name: {:via, Registry, {Duet.EntryRegistry, name}})
  end

  @impl true
  def init(config) do
    Registry.put_meta(Duet.EntryRegistry, {:entry_failure, config.name}, %{
      status: :unavailable,
      reason: nil
    })

    state = %{
      name: config.name,
      role: config.role,
      command: command(config),
      cwd: Path.dirname(Duet.Config.config_file_path()),
      port: nil,
      buf: "",
      status: :starting,
      conversation_id: nil,
      first_turn: true,
      pending_call: nil,
      pending_posts: :queue.new(),
      handoff: nil,
      initialize_timer: nil,
      startup_error: nil,
      interrupt_call: nil,
      interrupt_timer: nil,
      turn_result: nil
    }

    {:ok, open_session(state)}
  end

  defp command(config) do
    args = [
      "--input-format",
      "stream-json",
      "--output-format",
      "stream-json",
      "--mode",
      config.mode
    ]

    args = if config.model, do: args ++ ["--model", config.model], else: args

    args =
      if config.reasoning_effort, do: args ++ ["--effort", config.reasoning_effort], else: args

    # Replace the Port's shell so its OS PID can receive SIGINT directly.
    "exec env -- " <>
      config.command <> " " <> Enum.map_join(args, " ", &AppServerCommon.shell_escape/1)
  end

  @impl true
  def handle_call(:get_role, _from, state), do: {:reply, state.role, state}
  def handle_call(:get_status, _from, state), do: {:reply, Duet.entry_status(state, :agy), state}

  def handle_call({op, prompt}, from, state) when op in [:post, :enqueue] do
    if slash_command?(prompt),
      do: {:reply, {:error, :unsupported_slash_command}, state},
      else: handle_prompt(op, prompt, from, state)
  end

  def handle_call(:interrupt, _from, %{status: :idle} = state),
    do: {:reply, {:error, :not_running}, state}

  def handle_call(:interrupt, _from, %{status: :interrupting} = state),
    do: {:reply, {:error, :interrupting}, state}

  def handle_call(:interrupt, _from, %{status: :interrupt_unknown} = state),
    do: {:reply, {:error, :interrupt_timeout}, state}

  def handle_call(:interrupt, from, %{status: status} = state)
      when status in [:waiting, :compacting_summary] do
    case signal(state.port, "-INT") do
      :ok ->
        timer = Process.send_after(self(), {:interrupt_timeout, state.port}, @interrupt_timeout)
        {:noreply, %{state | status: :interrupting, interrupt_call: from, interrupt_timer: timer}}

      :error ->
        {:reply, {:error, :not_interruptible}, state}
    end
  end

  def handle_call(:interrupt, _from, state), do: {:reply, {:error, :not_interruptible}, state}

  @impl true
  def handle_cast({:enqueue, prompt}, state) do
    if slash_command?(prompt) do
      Logger.warning("#{log_prefix(state)} dropped unsupported slash command reservation")
      {:noreply, state}
    else
      {:noreply, enqueue(state, prompt)}
    end
  end

  @impl true
  def handle_info({port, {:data, {:eol, chunk}}}, %{port: port} = state) do
    next =
      AppServerCommon.decode_and_process(
        state.buf <> chunk,
        %{state | buf: ""},
        &process_message/2,
        log_prefix(state)
      )

    {:noreply, next}
  end

  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state),
    do: {:noreply, %{state | buf: state.buf <> chunk}}

  def handle_info({port, {:exit_status, _status}}, %{port: port, status: :clearing} = state),
    do: {:noreply, open_session(state)}

  def handle_info({port, {:exit_status, status}}, %{port: port, status: phase} = state)
      when phase in [:interrupting, :interrupt_unknown] do
    if state.interrupt_timer, do: Process.cancel_timer(state.interrupt_timer)
    {interrupt_result, post_result} = interrupt_results(state.turn_result, status)
    reply(state.interrupt_call, interrupt_result)
    reply(state.pending_call, post_result)

    # SIGINT closes the stream. Wait for its exit before resuming, so reserved
    # prompts cannot reach the interrupted process.
    state = %{state | pending_call: nil, interrupt_call: nil, interrupt_timer: nil}
    {:noreply, open_session(state, state.conversation_id)}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port, status: :initializing} = state) do
    reason = state.startup_error || {:port_exit, status}
    startup_failure(state, reason)
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    reason = {:port_exit, status}
    reply(state.pending_call, {:error, reason})
    {:stop, reason, state}
  end

  def handle_info({:initialize_timeout, port}, %{port: port, status: :initializing} = state),
    do: startup_failure(state, state.startup_error || :initialize_timeout)

  def handle_info({:interrupt_timeout, port}, %{port: port, status: :interrupting} = state) do
    reply(state.interrupt_call, {:error, :interrupt_timeout})
    reply(state.pending_call, {:error, :interrupt_timeout})

    {:noreply,
     %{
       state
       | status: :interrupt_unknown,
         interrupt_call: nil,
         pending_call: nil,
         interrupt_timer: nil
     }}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    if reason not in [:normal, :shutdown], do: Duet.record_entry_failure(state.name, reason)
    close_port(state.port)
  end

  defp handle_prompt(:enqueue, prompt, _from, state), do: {:reply, :ok, enqueue(state, prompt)}

  defp handle_prompt(:post, "/clear", from, %{status: :interrupt_unknown} = state) do
    case signal(state.port, "-KILL") do
      :ok -> {:noreply, %{state | status: :clearing, pending_call: from}}
      :error -> {:reply, {:error, :interrupt_timeout}, state}
    end
  end

  defp handle_prompt(:post, _prompt, _from, %{status: :interrupt_unknown} = state),
    do: {:reply, {:error, :interrupt_timeout}, state}

  defp handle_prompt(:post, prompt, from, %{status: :idle} = state),
    do: {:noreply, start_post(state, prompt, from)}

  defp handle_prompt(:post, _prompt, _from, state), do: {:reply, {:error, :busy}, state}

  # Without --disable-slash-commands (it also disables --mode), agy expands
  # slash commands, and CLI-handled ones end the stream session.
  defp slash_command?(prompt) when prompt in ["/clear", "/compact"], do: false
  defp slash_command?(prompt), do: String.starts_with?(String.trim_leading(prompt), "/")

  defp open_session(state, conversation_id \\ nil) do
    command =
      if conversation_id,
        do: state.command <> " --conversation " <> AppServerCommon.shell_escape(conversation_id),
        else: state.command

    port = AppServerCommon.start_app_server(command, state.cwd, @line_bytes, state.name)
    timer = Process.send_after(self(), {:initialize_timeout, port}, @initialize_timeout)

    %{
      state
      | port: port,
        buf: "",
        status: :initializing,
        conversation_id: conversation_id,
        first_turn: is_nil(conversation_id),
        initialize_timer: timer,
        startup_error: nil,
        turn_result: nil
    }
  end

  defp process_message(
         %{"event" => "init", "conversation_id" => id},
         %{status: :initializing} = state
       )
       when is_binary(id) and id != "" do
    Process.cancel_timer(state.initialize_timer)
    Logger.info("#{log_prefix(state)} ready (agy)")
    state = %{state | conversation_id: id, status: :idle, initialize_timer: nil}

    case state.handoff do
      nil ->
        finish(state, {:ok, ""})

      summary ->
        start_post(
          %{state | handoff: nil},
          build_compact_handoff_prompt(summary),
          state.pending_call
        )
    end
  end

  defp process_message(
         %{"event" => "result", "result" => result},
         %{status: :initializing} = state
       ) do
    %{state | startup_error: {:initialize_failed, agy_error(result)}}
  end

  defp process_message(%{"event" => "result", "result" => result}, %{status: status} = state)
       when is_map(result) and status in [:interrupting, :interrupt_unknown] do
    # A turn that finished before SIGINT is followed by agy's own interrupted
    # result for the idle stream. Keep the first one.
    %{state | turn_result: state.turn_result || result}
  end

  defp process_message(%{"event" => "result", "result" => result}, %{status: status} = state)
       when is_map(result) and status in [:waiting, :compacting_summary] do
    case {state.status, turn_result(result)} do
      {:compacting_summary, {:ok, ""}} ->
        finish(state, {:error, :empty_compact_summary})

      {:compacting_summary, {:ok, summary}} ->
        close_port(state.port)
        open_session(%{state | handoff: summary})

      {_status, response} ->
        finish(state, with_denied_note(response, result))
    end
  end

  defp process_message(_message, state), do: state

  defp start_post(state, "/clear", from) do
    close_port(state.port)
    open_session(%{state | pending_call: from})
  end

  defp start_post(state, "/compact", from) do
    send_prompt(state, build_compact_summary_prompt())
    %{state | status: :compacting_summary, pending_call: from}
  end

  defp start_post(state, prompt, from) do
    [%{text: text}] = build_turn_input(state, prompt)
    send_prompt(state, text)
    %{state | status: :waiting, pending_call: from, first_turn: false}
  end

  defp send_prompt(state, text) do
    Port.command(state.port, JSON.encode!(%{event: "user", message: %{content: text}}) <> "\n")
  rescue
    # The Port may exit between the queue check and this write. Its exit status
    # will resolve the pending call.
    ArgumentError -> :ok
  end

  defp turn_result(%{"status" => "SUCCESS", "response" => response}) when is_binary(response),
    do: {:ok, String.trim(response)}

  defp turn_result(result) do
    if interrupted?(result),
      do: {:error, "interrupted"},
      else: {:error, {:agy_error, agy_error(result)}}
  end

  defp interrupted?(%{"finished_reason" => "interrupted"}), do: true
  defp interrupted?(%{"status" => status}), do: status in ["INTERRUPTED", "CANCELED"]
  defp interrupted?(_result), do: false

  defp agy_error(%{"error" => error}) when is_binary(error) and error != "", do: error
  defp agy_error(%{"status" => status}) when is_binary(status), do: status
  defp agy_error(_result), do: "unknown error"

  defp interrupt_results(nil, exit) do
    error = {:error, {:port_exit, exit}}
    {error, error}
  end

  defp interrupt_results(result, _exit) do
    if interrupted?(result),
      do: {:ok, {:error, "interrupted"}},
      else: {{:error, :not_running}, with_denied_note(turn_result(result), result)}
  end

  # Headless agy denies actions it cannot ask about and ends the turn with a
  # partial SUCCESS response. Tell the caller why the answer may be incomplete.
  defp with_denied_note({:ok, response}, %{"denied_actions" => [_ | _] = actions}) do
    names =
      actions
      |> Enum.map(fn action -> action["display_name"] || action["action"] || "unknown" end)
      |> Enum.uniq()
      |> Enum.join(", ")

    note = "[Duet] agy の権限設定により拒否された操作: #{names}。応答が途中の可能性があります。"
    {:ok, String.trim(response <> "\n\n" <> note)}
  end

  defp with_denied_note(response, _result), do: response

  defp startup_failure(state, reason) do
    Logger.error("#{log_prefix(state)} startup failed: #{inspect(reason)}")
    reply(state.pending_call, {:error, reason})
    {:stop, {:shutdown, reason}, state}
  end

  defp finish(state, result) do
    reply(state.pending_call, result)
    state = %{state | status: :idle, pending_call: nil}

    case :queue.out(state.pending_posts) do
      {{:value, prompt}, rest} -> start_post(%{state | pending_posts: rest}, prompt, nil)
      {:empty, _} -> state
    end
  end

  defp enqueue(%{status: :idle} = state, prompt), do: start_post(state, prompt, nil)

  defp enqueue(state, prompt),
    do: %{state | pending_posts: :queue.in(prompt, state.pending_posts)}

  defp signal(port, signal) do
    with {:os_pid, pid} <- Port.info(port, :os_pid),
         {_output, 0} <-
           System.cmd("kill", [signal, Integer.to_string(pid)], stderr_to_stdout: true) do
      :ok
    else
      _ -> :error
    end
  end

  defp reply(nil, _result), do: :ok
  defp reply(from, result), do: GenServer.reply(from, result)

  defp close_port(port) do
    if Port.info(port), do: Port.close(port)
  end

  defp log_prefix(state), do: "[Duet.AgyEntry:#{state.name}]"
end
