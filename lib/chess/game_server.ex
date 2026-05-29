defmodule Chess.GameServer do
  @moduledoc """
  GenServer que detém uma única partida de xadrez ao vivo.

  Responsibilities: OTP lifecycle, PubSub broadcast, connection tracking,
  and auto-resign timers. All coordination between domain and engine
  is delegated to `Chess.GameSession`.

  Registrado em `Chess.GameRegistry` por `room_id`, iniciado sob
  `Chess.GameSupervisor`.
  """
  use GenServer, restart: :transient

  alias Chess.Game
  alias Chess.GameSession

  @pubsub Chess.PubSub

  defmodule State do
    @enforce_keys [:session]
    defstruct [
      :session,
      started_at: nil,
      connections: %{},
      pending_resigns: %{},
      shutdown_timer: nil
    ]
  end

  ## Client API

  def start_link(%{room_id: room_id} = opts) do
    GenServer.start_link(__MODULE__, opts, name: via(room_id))
  end

  def get_state(room_id), do: GenServer.call(via(room_id), :get_state)

  def legal_moves_from(room_id, square),
    do: GenServer.call(via(room_id), {:legal_moves_from, square})

  def move(room_id, nickname, from, to, promotion \\ nil),
    do: GenServer.call(via(room_id), {:move, nickname, from, to, promotion})

  def resign(room_id, nickname),
    do: GenServer.call(via(room_id), {:resign, nickname})

  def join(room_id, pid, nickname),
    do: GenServer.call(via(room_id), {:join, pid, nickname})

  def stop(room_id), do: GenServer.stop(via(room_id))

  def via(room_id), do: {:via, Registry, {Chess.GameRegistry, room_id}}

  ## Server callbacks

  @impl true
  def init(opts), do: {:ok, opts, {:continue, :start_engine}}

  @impl true
  def handle_continue(:start_engine, %{
        room_id: room_id,
        mode: mode,
        white: white,
        black: black,
        instance_sup: instance_sup
      }) do
    engine_pid = find_engine(instance_sup)
    session = GameSession.from_pid(room_id, mode, white, black, engine_pid)

    state = %State{session: session, started_at: System.system_time(:second)}
    {:noreply, schedule_shutdown_check(state, join_timeout_ms())}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, GameSession.public_state(state.session), state}
  end

  def handle_call({:legal_moves_from, square}, _from, state) do
    {:reply, GameSession.legal_moves_from(state.session, square), state}
  end

  def handle_call({:move, nickname, from, to, promo}, _from, state) do
    case GameSession.move(state.session, nickname, from, to, promo) do
      {:ok, new_session} ->
        new_state = %State{state | session: new_session}
        broadcast(new_state)
        {:reply, {:ok, GameSession.public_state(new_session)}, new_state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call(
        {:resign, nickname},
        _from,
        %State{session: %GameSession{game: %Game{mode: :solo}}} = state
      ) do
    case GameSession.resign(state.session, nickname) do
      {:ok, new_session} ->
        new_state = %State{state | session: new_session}
        broadcast(new_state)
        {:reply, {:ok, GameSession.public_state(new_session)}, new_state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call({:resign, nickname}, _from, state) do
    case GameSession.resign(state.session, nickname) do
      {:ok, new_session} ->
        new_state = %State{state | session: new_session}
        broadcast(new_state)
        {:reply, {:ok, GameSession.public_state(new_session)}, new_state}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  def handle_call({:join, pid, nickname}, _from, state) do
    if GameSession.player?(state.session, nickname) do
      was_pending? = Map.has_key?(state.pending_resigns, nickname)

      new_state =
        state
        |> register_connection(pid, nickname)
        |> cancel_pending_resign(nickname)
        |> cancel_shutdown_timer()

      if was_pending?, do: broadcast_reconnect(new_state, nickname)

      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case Map.pop(state.connections, pid) do
      {nil, _} ->
        {:noreply, state}

      {{nickname, _ref}, remaining} ->
        new_state =
          %State{state | connections: remaining}
          |> maybe_schedule_auto_resign(nickname)
          |> maybe_schedule_shutdown()

        {:noreply, new_state}
    end
  end

  def handle_info({:auto_resign, nickname}, state) do
    new_state = %State{state | pending_resigns: Map.delete(state.pending_resigns, nickname)}
    g = new_state.session.game

    resolved =
      cond do
        g.status != :in_progress ->
          new_state

        g.mode == :solo ->
          new_state

        reconnected?(new_state, nickname) ->
          new_state

        true ->
          case GameSession.resign(new_state.session, nickname) do
            {:ok, new_session} ->
              resigned_state = %State{new_state | session: new_session}
              broadcast(resigned_state)
              resigned_state

            {:error, _} ->
              new_state
          end
      end

    {:noreply, maybe_schedule_shutdown(resolved)}
  end

  def handle_info(:shutdown_check, %State{connections: connections} = state)
      when map_size(connections) == 0 do
    {:stop, :normal, state}
  end

  def handle_info(:shutdown_check, state) do
    {:noreply, %State{state | shutdown_timer: nil}}
  end

  ## Helpers

  defp find_engine(instance_sup) do
    instance_sup
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {Chess.GameEngine, pid, _, _} when is_pid(pid) -> pid
      _ -> nil
    end)
  end

  defp broadcast(%State{session: session}) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "game:" <> session.game.room_id,
      {:game_state, GameSession.public_state(session)}
    )
  end

  defp register_connection(state, pid, nickname) do
    if Map.has_key?(state.connections, pid) do
      state
    else
      ref = Process.monitor(pid)
      %State{state | connections: Map.put(state.connections, pid, {nickname, ref})}
    end
  end

  defp cancel_pending_resign(state, nickname) do
    case Map.pop(state.pending_resigns, nickname) do
      {nil, _} ->
        state

      {timer_ref, remaining} ->
        Process.cancel_timer(timer_ref)
        %State{state | pending_resigns: remaining}
    end
  end

  defp maybe_schedule_auto_resign(
         %State{session: %GameSession{game: %Game{mode: :solo}}} = state,
         _nickname
       ),
       do: state

  defp maybe_schedule_auto_resign(
         %State{session: %GameSession{game: %Game{status: status}}} = state,
         _nickname
       )
       when status != :in_progress,
       do: state

  defp maybe_schedule_auto_resign(state, nickname) do
    if has_other_connection?(state, nickname) do
      state
    else
      state = cancel_pending_resign(state, nickname)
      grace = grace_ms()
      timer_ref = Process.send_after(self(), {:auto_resign, nickname}, grace)
      deadline_ms = System.system_time(:millisecond) + grace
      broadcast_disconnect(state, nickname, deadline_ms)
      %State{state | pending_resigns: Map.put(state.pending_resigns, nickname, timer_ref)}
    end
  end

  defp broadcast_disconnect(%State{session: session}, nickname, deadline_ms) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "game:" <> session.game.room_id,
      {:opponent_disconnected, nickname, deadline_ms}
    )
  end

  defp broadcast_reconnect(%State{session: session}, nickname) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "game:" <> session.game.room_id,
      {:opponent_reconnected, nickname}
    )
  end

  defp reconnected?(state, nickname), do: has_other_connection?(state, nickname)

  defp has_other_connection?(state, nickname) do
    Enum.any?(state.connections, fn {_pid, {nick, _ref}} -> nick == nickname end)
  end

  defp grace_ms, do: Application.get_env(:chess, Chess.GameServer, [])[:resign_grace_ms]
  defp join_timeout_ms, do: Application.get_env(:chess, Chess.GameServer, [])[:join_timeout_ms]

  defp shutdown_grace_ms,
    do: Application.get_env(:chess, Chess.GameServer, [])[:shutdown_grace_ms]

  defp maybe_schedule_shutdown(%State{connections: connections} = state)
       when map_size(connections) == 0 do
    schedule_shutdown_check(cancel_shutdown_timer(state), shutdown_grace_ms())
  end

  defp maybe_schedule_shutdown(state), do: state

  defp schedule_shutdown_check(state, grace_ms) do
    timer_ref = Process.send_after(self(), :shutdown_check, grace_ms)
    %State{state | shutdown_timer: timer_ref}
  end

  defp cancel_shutdown_timer(%State{shutdown_timer: nil} = state), do: state

  defp cancel_shutdown_timer(%State{shutdown_timer: ref} = state) do
    Process.cancel_timer(ref)
    %State{state | shutdown_timer: nil}
  end
end
