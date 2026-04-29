defmodule Chess.GameSession do
  @moduledoc """
  Facade de coordenação para uma sessão de jogo ativa.

  Wraps the `{%Chess.Game{}, game_pid}` pair and provides the operations that
  compose `Chess.Games` (pure rules) and `Chess.GameEngine` (binbo wrapper).

  No OTP, no PubSub, no connection tracking. Every function returns
  `{:ok, %GameSession{}}` or `{:error, reason}`, making it easy to test in isolation.
  """

  alias Chess.GameEngine
  alias Chess.Games

  @enforce_keys [:game, :game_pid]
  defstruct [:game, :game_pid]

  @type t :: %__MODULE__{
          game: Chess.Game.t(),
          game_pid: pid()
        }

  @spec new(String.t(), :solo | :multiplayer, String.t(), String.t()) ::
          {:ok, t()} | {:error, term()}
  def new(room_id, mode, white, black) do
    with {:ok, game_pid} <- GameEngine.new() do
      {:ok, %__MODULE__{game: Games.new(room_id, mode, white, black), game_pid: game_pid}}
    end
  end

  @spec move(t(), String.t(), String.t(), String.t(), atom() | nil) ::
          {:ok, t()} | {:error, term()}
  def move(%__MODULE__{game: g, game_pid: game_pid} = session, nickname, from, to, promo) do
    with :ok <- Games.ensure_in_progress(g.status),
         {:ok, _color} <- Games.color_for(g.mode, g.players, nickname),
         :ok <- Games.ensure_turn_for(g.mode, g.players, g.side_to_move, nickname),
         {:ok, new_status} <- GameEngine.move(game_pid, from, to, promo) do
      move_record = %{from: from, to: to, color: g.side_to_move, promotion: promo}
      new_game = Games.apply_move(g, move_record, new_status, GameEngine.side_to_move(game_pid))
      {:ok, %__MODULE__{session | game: new_game}}
    end
  end

  @spec resign(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def resign(%__MODULE__{game: %Chess.Game{mode: :solo} = g} = session, nickname) do
    with :ok <- Games.ensure_in_progress(g.status),
         {:ok, _color} <- Games.color_for(g.mode, g.players, nickname) do
      {:ok, %__MODULE__{session | game: Games.apply_solo_resign(g)}}
    end
  end

  def resign(%__MODULE__{game: g, game_pid: game_pid} = session, nickname) do
    with {:ok, new_game, winner} <- Games.apply_multiplayer_resign(g, nickname),
         :ok <- GameEngine.set_winner(game_pid, winner, :resign) do
      {:ok, %__MODULE__{session | game: new_game}}
    end
  end

  @spec legal_moves_from(t(), String.t()) :: [String.t()]
  def legal_moves_from(%__MODULE__{game_pid: game_pid}, square),
    do: GameEngine.legal_moves_from(game_pid, square)

  @spec player?(t(), String.t()) :: boolean()
  def player?(%__MODULE__{game: g}, nickname),
    do: match?({:ok, _}, Games.color_for(g.mode, g.players, nickname))

  @spec public_state(t()) :: map()
  def public_state(%__MODULE__{game: g, game_pid: game_pid}) do
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

  @spec stop(t()) :: :ok
  def stop(%__MODULE__{game_pid: game_pid}), do: GameEngine.stop(game_pid)
end
