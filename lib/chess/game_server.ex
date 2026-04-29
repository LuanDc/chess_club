defmodule Chess.GameServer do
  @moduledoc """
  GenServer that owns a single live chess game. Wraps `Chess.GameEngine`,
  enforces turn order, tracks history, and broadcasts every state
  change on `"game:<room_id>"` via `Chess.PubSub`.

  Registered through `Chess.GameRegistry` keyed by `room_id`, started
  under `Chess.GameSupervisor`.
  """
  use GenServer, restart: :transient

  alias Chess.Game
  alias Chess.GameEngine
  alias Chess.Games

  @pubsub Chess.PubSub

  defmodule State do
    @enforce_keys [:game, :game_pid]
    defstruct [
      :game,
      :game_pid,
      started_at: nil,
      connections: %{},
      pending_resigns: %{}
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
  def init(%{room_id: room_id, mode: mode, white: white, black: black}) do
    {:ok, game_pid} = GameEngine.new()

    state = %State{
      game: Games.new(room_id, mode, white, black),
      game_pid: game_pid,
      started_at: System.system_time(:second)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, public_state(state), state}
  end

  def handle_call({:legal_moves_from, square}, _from, state) do
    {:reply, GameEngine.legal_moves_from(state.game_pid, square), state}
  end

  def handle_call({:move, nickname, from, to, promo}, _from, state) do
    g = state.game

    with :ok <- Games.ensure_in_progress(g.status),
         {:ok, _color} <- Games.color_for(g.mode, g.players, nickname),
         :ok <- Games.ensure_turn_for(g.mode, g.players, g.side_to_move, nickname),
         {:ok, new_status} <- GameEngine.move(state.game_pid, from, to, promo) do
      move_record = %{from: from, to: to, color: g.side_to_move, promotion: promo}

      new_game =
        Games.apply_move(g, move_record, new_status, GameEngine.side_to_move(state.game_pid))

      new_state = %State{state | game: new_game}
      broadcast(new_state)
      {:reply, {:ok, public_state(new_state)}, new_state}
    else
      {:error, _} = err -> {:reply, err, state}
    end
  end

  def handle_call({:resign, nickname}, _from, %State{game: %Game{mode: :solo}} = state) do
    g = state.game

    with :ok <- Games.ensure_in_progress(g.status),
         {:ok, _color} <- Games.color_for(g.mode, g.players, nickname) do
      new_state = %State{state | game: Games.apply_solo_resign(g)}
      broadcast(new_state)
      {:reply, {:ok, public_state(new_state)}, new_state}
    else
      err -> {:reply, err, state}
    end
  end

  def handle_call({:resign, nickname}, _from, state) do
    case do_multiplayer_resign(state, nickname) do
      {:ok, new_state} -> {:reply, {:ok, public_state(new_state)}, new_state}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  def handle_call({:join, pid, nickname}, _from, state) do
    case Games.color_for(state.game.mode, state.game.players, nickname) do
      {:error, :not_a_player} ->
        {:reply, :ok, state}

      {:ok, _color} ->
        new_state =
          state
          |> register_connection(pid, nickname)
          |> cancel_pending_resign(nickname)

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case Map.pop(state.connections, pid) do
      {nil, _} ->
        {:noreply, state}

      {{nickname, _ref}, remaining} ->
        new_state = %State{state | connections: remaining}
        {:noreply, maybe_schedule_auto_resign(new_state, nickname)}
    end
  end

  def handle_info({:auto_resign, nickname}, state) do
    new_state = %State{state | pending_resigns: Map.delete(state.pending_resigns, nickname)}
    g = new_state.game

    cond do
      g.status != :in_progress ->
        {:noreply, new_state}

      g.mode == :solo ->
        {:noreply, new_state}

      reconnected?(new_state, nickname) ->
        {:noreply, new_state}

      true ->
        case do_multiplayer_resign(new_state, nickname) do
          {:ok, resigned_state} -> {:noreply, resigned_state}
          {:error, _} -> {:noreply, new_state}
        end
    end
  end

  @impl true
  def terminate(_reason, %State{game_pid: pid}) do
    GameEngine.stop(pid)
    :ok
  end

  ## Helpers

  defp public_state(%State{game: g, game_pid: game_pid}) do
    %{
      room_id: g.room_id,
      mode: g.mode,
      players: g.players,
      side_to_move: g.side_to_move,
      status: g.status,
      history: g.history,
      fen: GameEngine.fen(game_pid)
    }
  end

  defp broadcast(%State{game: %Game{room_id: room_id}} = state) do
    Phoenix.PubSub.broadcast(@pubsub, "game:" <> room_id, {:game_state, public_state(state)})
  end

  defp do_multiplayer_resign(state, nickname) do
    case Games.apply_multiplayer_resign(state.game, nickname) do
      {:ok, new_game, winner} ->
        :ok = GameEngine.set_winner(state.game_pid, winner, :resign)
        new_state = %State{state | game: new_game}
        broadcast(new_state)
        {:ok, new_state}

      {:error, _} = err ->
        err
    end
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

  defp maybe_schedule_auto_resign(%State{game: %Game{mode: :solo}} = state, _nickname), do: state

  defp maybe_schedule_auto_resign(%State{game: %Game{status: status}} = state, _nickname)
       when status != :in_progress,
       do: state

  defp maybe_schedule_auto_resign(state, nickname) do
    if has_other_connection?(state, nickname) do
      state
    else
      state = cancel_pending_resign(state, nickname)
      timer_ref = Process.send_after(self(), {:auto_resign, nickname}, grace_ms())
      %State{state | pending_resigns: Map.put(state.pending_resigns, nickname, timer_ref)}
    end
  end

  defp reconnected?(state, nickname), do: has_other_connection?(state, nickname)

  defp has_other_connection?(state, nickname) do
    Enum.any?(state.connections, fn {_pid, {nick, _ref}} -> nick == nickname end)
  end

  defp grace_ms, do: Application.get_env(:chess, :resign_grace_ms, 30_000)
end
