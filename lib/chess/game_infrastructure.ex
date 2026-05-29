defmodule Chess.GameInfrastructure do
  @moduledoc """
  Supervisor that groups all game-domain infrastructure processes:
  lobby rooms, game registries, and the dynamic game supervisor.
  """
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      Chess.Rooms,
      {Registry, keys: :unique, name: Chess.GameRegistry},
      {Registry, keys: :unique, name: Chess.GameInstanceRegistry},
      {DynamicSupervisor, name: Chess.GameSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
