defmodule Chess.GameInstance do
  @moduledoc """
  Per-game supervision subtree. Supervises a `Chess.GameEngine` (engine
  wrapper that owns binbo and self-heals on crash) and a `Chess.GameSession`
  (domain/PubSub/connection tracking) with `:rest_for_one` so that an
  engine-tier failure cascades into a GameSession restart, while a GameSession
  crash leaves the engine running.

  Registered by `room_id` in `Chess.GameInstanceRegistry`. Started under
  `Chess.GameSupervisor` by `Chess.GameSessions.start_game/1`.
  """
  use Supervisor, restart: :transient

  def start_link(%{room_id: room_id} = opts) do
    Supervisor.start_link(__MODULE__, opts, name: via(room_id))
  end

  def via(room_id), do: {:via, Registry, {Chess.GameInstanceRegistry, room_id}}

  @impl true
  def init(opts) do
    children = [
      Chess.GameEngine,
      {Chess.GameSession, Map.put(opts, :instance_sup, self())}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
