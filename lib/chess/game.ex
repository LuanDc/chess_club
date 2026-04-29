defmodule Chess.Game do
  @moduledoc "Game state schema."

  @enforce_keys [:room_id, :mode, :players]
  defstruct [
    :room_id,
    :mode,
    :players,
    side_to_move: :white,
    status: :in_progress,
    history: []
  ]

  @type t :: %__MODULE__{
          room_id: String.t(),
          mode: :solo | :multiplayer,
          players: %{white: String.t(), black: String.t()},
          side_to_move: :white | :black,
          status:
            :in_progress
            | :ended
            | {:checkmate, term()}
            | {:winner, :white | :black, term()},
          history: [map()]
        }
end
