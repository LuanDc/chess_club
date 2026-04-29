defmodule Chess.Games do
  @moduledoc """
  Public façade for live games. Delegates to `Chess.GameServer`
  processes spawned under `Chess.GameSupervisor` and looked up
  through `Chess.GameRegistry`.
  """

  alias Chess.GameServer

  @registry Chess.GameRegistry
  @supervisor Chess.GameSupervisor

  @doc """
  Starts a game. `opts` is a map with:

      %{room_id: "ABC123", mode: :multiplayer | :solo, white: "Alice", black: "Bob"}
  """
  def start_game(%{room_id: _, mode: _, white: _, black: _} = opts) do
    DynamicSupervisor.start_child(@supervisor, {GameServer, opts})
  end

  def lookup(room_id) do
    case Registry.lookup(@registry, room_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def get_state(room_id), do: GameServer.get_state(room_id)

  def legal_moves_from(room_id, square), do: GameServer.legal_moves_from(room_id, square)

  def move(room_id, nickname, from, to, promotion \\ nil),
    do: GameServer.move(room_id, nickname, from, to, promotion)

  def resign(room_id, nickname), do: GameServer.resign(room_id, nickname)

  def join(room_id, pid, nickname), do: GameServer.join(room_id, pid, nickname)

  def stop(room_id) do
    case lookup(room_id) do
      {:ok, pid} -> DynamicSupervisor.terminate_child(@supervisor, pid)
      err -> err
    end
  end
end
