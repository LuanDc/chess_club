defmodule Chess.GameServer do
  @moduledoc """
  GenServer that owns a single live chess game. Wraps `Chess.Game`,
  enforces turn order, tracks history, and broadcasts every state
  change on `"game:<room_id>"` via `Chess.PubSub`.

  Registered through `Chess.GameRegistry` keyed by `room_id`, started
  under `Chess.GameSupervisor`.
  """
  use GenServer, restart: :transient

  alias Chess.Game

  @pubsub Chess.PubSub

  defmodule State do
    @enforce_keys [:room_id, :mode, :players, :game_pid]
    defstruct [
      :room_id,
      :mode,
      :players,
      :game_pid,
      side_to_move: :white,
      status: :in_progress,
      history: [],
      started_at: nil
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

  def stop(room_id), do: GenServer.stop(via(room_id))

  def via(room_id), do: {:via, Registry, {Chess.GameRegistry, room_id}}

  ## Server callbacks

  @impl true
  def init(%{room_id: room_id, mode: mode, white: white, black: black}) do
    {:ok, game_pid} = Game.new()

    state = %State{
      room_id: room_id,
      mode: mode,
      players: %{white: white, black: black},
      game_pid: game_pid,
      side_to_move: :white,
      status: :in_progress,
      history: [],
      started_at: System.system_time(:second)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, public_state(state), state}
  end

  def handle_call({:legal_moves_from, square}, _from, state) do
    {:reply, Game.legal_moves_from(state.game_pid, square), state}
  end

  def handle_call({:move, nickname, from, to, promo}, _from, state) do
    with :ok <- ensure_in_progress(state),
         {:ok, _color} <- color_for(state, nickname),
         :ok <- ensure_turn_for(state, nickname),
         {:ok, status} <- Game.move(state.game_pid, from, to, promo) do
      played_color = state.side_to_move
      move_record = %{from: from, to: to, color: played_color, promotion: promo}

      new_state = %State{
        state
        | history: state.history ++ [move_record],
          status: status,
          side_to_move: Game.side_to_move(state.game_pid)
      }

      broadcast(new_state)
      {:reply, {:ok, public_state(new_state)}, new_state}
    else
      {:error, _} = err -> {:reply, err, state}
    end
  end

  def handle_call({:resign, nickname}, _from, %State{mode: :solo} = state) do
    with :ok <- ensure_in_progress(state),
         {:ok, _color} <- color_for(state, nickname) do
      new_state = %State{state | status: :ended}
      broadcast(new_state)
      {:reply, {:ok, public_state(new_state)}, new_state}
    else
      err -> {:reply, err, state}
    end
  end

  def handle_call({:resign, nickname}, _from, state) do
    with :ok <- ensure_in_progress(state),
         {:ok, color} <- color_for(state, nickname) do
      winner = other_color(color)
      :ok = Game.set_winner(state.game_pid, winner, :resign)
      new_status = {:winner, winner, :resign}
      new_state = %State{state | status: new_status}
      broadcast(new_state)
      {:reply, {:ok, public_state(new_state)}, new_state}
    else
      err -> {:reply, err, state}
    end
  end

  @impl true
  def terminate(_reason, %State{game_pid: pid}) do
    Game.stop(pid)
    :ok
  end

  ## Helpers

  defp public_state(%State{} = s) do
    %{
      room_id: s.room_id,
      mode: s.mode,
      players: s.players,
      side_to_move: s.side_to_move,
      status: s.status,
      history: s.history,
      fen: Game.fen(s.game_pid)
    }
  end

  defp broadcast(%State{room_id: room_id} = s) do
    Phoenix.PubSub.broadcast(@pubsub, "game:" <> room_id, {:game_state, public_state(s)})
  end

  defp ensure_in_progress(%State{status: :in_progress}), do: :ok
  defp ensure_in_progress(_), do: {:error, :game_over}

  defp color_for(%State{mode: :solo, players: %{white: nick}}, nick), do: {:ok, :solo}

  defp color_for(%State{players: %{white: nick}}, nick), do: {:ok, :white}
  defp color_for(%State{players: %{black: nick}}, nick), do: {:ok, :black}
  defp color_for(_, _), do: {:error, :not_a_player}

  defp ensure_turn_for(%State{mode: :solo}, _nickname), do: :ok

  defp ensure_turn_for(%State{side_to_move: side_color, players: players}, nickname) do
    if Map.get(players, side_color) == nickname do
      :ok
    else
      {:error, :not_your_turn}
    end
  end

  defp other_color(:white), do: :black
  defp other_color(:black), do: :white
end
