defmodule Chess.GameSessions do
  @moduledoc """
  OTP facade for live games. Each game runs as a `Chess.GameInstance`
  supervision subtree spawned under `Chess.GameSupervisor`. The instance
  is registered by `room_id` in `Chess.GameInstanceRegistry`; the inner
  `Chess.GameSession` is registered under the same `room_id` in
  `Chess.GameRegistry`.
  """

  alias Chess.GameInstance
  alias Chess.GameSession

  @registry Chess.GameRegistry
  @instance_registry Chess.GameInstanceRegistry
  @supervisor Chess.GameSupervisor

  @doc """
  Starts a game. `opts` is a map with:

      %{room_id: "ABC123", mode: :multiplayer | :solo, white: "Alice", black: "Bob"}
  """
  def start_game(%{room_id: _, mode: _, white: _, black: _} = opts) do
    DynamicSupervisor.start_child(@supervisor, {GameInstance, opts})
  end

  def lookup(room_id) do
    case Registry.lookup(@registry, room_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def get_state(room_id), do: GameSession.get_state(room_id)

  def legal_moves_from(room_id, square), do: GameSession.legal_moves_from(room_id, square)

  def move(room_id, nickname, from, to, promotion \\ nil),
    do: GameSession.move(room_id, nickname, from, to, promotion)

  def resign(room_id, nickname), do: GameSession.resign(room_id, nickname)

  def join(room_id, pid, nickname), do: GameSession.join(room_id, pid, nickname)

  def stop(room_id) do
    case Registry.lookup(@instance_registry, room_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(@supervisor, pid)
      [] -> {:error, :not_found}
    end
  end
end
