defmodule Duet.BridgeLog do
  @moduledoc """
  Process-local activity log shared by the bridge side and Duet entries.

  Events and reader cursors live only for the lifetime of the Duet process.
  """

  use GenServer

  @type event :: %{
          sequence: pos_integer(),
          sender: String.t(),
          branch: String.t(),
          body: String.t(),
          inserted_at: DateTime.t()
        }

  @type state :: %{
          next_sequence: pos_integer(),
          events: [event()],
          cursors: %{optional(String.t()) => non_neg_integer()}
        }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Appends an event to the process-local log.
  """
  def publish(sender, branch, body)
      when is_binary(sender) and is_binary(branch) and is_binary(body) do
    with :ok <- validate_present(sender, :invalid_sender),
         :ok <- validate_present(branch, :invalid_branch),
         :ok <- validate_present(body, :invalid_body) do
      GenServer.call(__MODULE__, {:publish, sender, branch, body})
    end
  end

  def publish(_sender, _branch, _body), do: {:error, :invalid_event}

  @doc """
  Returns events after `reader`'s cursor and advances the cursor atomically.

  Events published by the reader are omitted from the result, but still advance
  the cursor.
  """
  def read_unread(reader) when is_binary(reader) do
    with :ok <- validate_present(reader, :invalid_reader) do
      GenServer.call(__MODULE__, {:read_unread, reader})
    end
  end

  def read_unread(_reader), do: {:error, :invalid_reader}

  @doc """
  Returns every event after `sequence` without changing any reader cursor.
  """
  def read_after(sequence) when is_integer(sequence) and sequence >= 0 do
    GenServer.call(__MODULE__, {:read_after, sequence})
  end

  def read_after(_sequence), do: {:error, :invalid_sequence}

  @doc """
  Removes all events and cursors and restarts sequencing at one.
  """
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(:ok) do
    {:ok, empty_state()}
  end

  @impl true
  def handle_call({:publish, sender, branch, body}, _from, state) do
    event = %{
      sequence: state.next_sequence,
      sender: sender,
      branch: branch,
      body: body,
      inserted_at: DateTime.utc_now()
    }

    next_state = %{
      state
      | next_sequence: state.next_sequence + 1,
        events: [event | state.events]
    }

    {:reply, {:ok, event}, next_state}
  end

  def handle_call({:read_unread, reader}, _from, state) do
    cursor = Map.get(state.cursors, reader, 0)
    latest_sequence = state.next_sequence - 1

    events =
      state.events
      |> Enum.reverse()
      |> Enum.filter(&(&1.sequence > cursor and &1.sender != reader))

    next_state = %{state | cursors: Map.put(state.cursors, reader, latest_sequence)}
    {:reply, {:ok, events}, next_state}
  end

  def handle_call({:read_after, sequence}, _from, state) do
    events =
      state.events
      |> Enum.reverse()
      |> Enum.filter(&(&1.sequence > sequence))

    {:reply, {:ok, events}, state}
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, empty_state()}
  end

  defp empty_state do
    %{next_sequence: 1, events: [], cursors: %{}}
  end

  defp validate_present(value, reason) do
    if String.trim(value) == "", do: {:error, reason}, else: :ok
  end
end
