defmodule Chess.Games do
  @moduledoc """
  Phoenix context for chess games.

  Pure business rule functions + public API that delegates to
  Chess.GamesServer for process-involving operations.
  """

  alias Chess.Game
  alias Chess.GamesServer

  ## Constructor

  @spec new(String.t(), :solo | :multiplayer, String.t(), String.t()) :: Game.t()
  def new(room_id, mode, white, black) do
    %Game{room_id: room_id, mode: mode, players: %{white: white, black: black}}
  end

  ## State transitions (pure)

  @spec apply_move(Game.t(), map(), term(), :white | :black) :: Game.t()
  def apply_move(%Game{} = game, move_record, new_status, next_side) do
    %Game{
      game
      | history: game.history ++ [move_record],
        status: new_status,
        side_to_move: next_side
    }
  end

  @spec apply_solo_resign(Game.t()) :: Game.t()
  def apply_solo_resign(%Game{} = game) do
    %Game{game | status: :ended}
  end

  @spec apply_multiplayer_resign(Game.t(), String.t()) ::
          {:ok, Game.t(), :white | :black} | {:error, term()}
  def apply_multiplayer_resign(%Game{mode: :solo}, _nickname) do
    {:error, :solo_mode}
  end

  def apply_multiplayer_resign(%Game{} = game, nickname) do
    with :ok <- ensure_in_progress(game.status),
         {:ok, color} <- color_for(game.mode, game.players, nickname) do
      winner = other_color(color)
      {:ok, %Game{game | status: {:winner, winner, :resign}}, winner}
    end
  end

  ## Validations (pure)

  @spec ensure_in_progress(term()) :: :ok | {:error, :game_over}
  def ensure_in_progress(:in_progress), do: :ok
  def ensure_in_progress(_), do: {:error, :game_over}

  @spec color_for(:solo | :multiplayer, map(), String.t()) ::
          {:ok, :solo | :white | :black} | {:error, :not_a_player}
  def color_for(:solo, %{white: nick}, nick), do: {:ok, :solo}
  def color_for(_mode, %{white: nick}, nick), do: {:ok, :white}
  def color_for(_mode, %{black: nick}, nick), do: {:ok, :black}
  def color_for(_mode, _players, _nick), do: {:error, :not_a_player}

  @spec ensure_turn_for(:solo | :multiplayer, map(), :white | :black, String.t()) ::
          :ok | {:error, :not_your_turn}
  def ensure_turn_for(:solo, _players, _side, _nickname), do: :ok

  def ensure_turn_for(_mode, players, side, nickname) do
    if Map.get(players, side) == nickname, do: :ok, else: {:error, :not_your_turn}
  end

  @spec other_color(:white | :black) :: :white | :black
  def other_color(:white), do: :black
  def other_color(:black), do: :white

  ## Public API (delegates to the OTP layer)

  defdelegate start_game(opts), to: GamesServer
  defdelegate lookup(room_id), to: GamesServer
  defdelegate get_state(room_id), to: GamesServer
  defdelegate legal_moves_from(room_id, square), to: GamesServer
  defdelegate move(room_id, nickname, from, to), to: GamesServer
  defdelegate move(room_id, nickname, from, to, promotion), to: GamesServer
  defdelegate resign(room_id, nickname), to: GamesServer
  defdelegate join(room_id, pid, nickname), to: GamesServer
  defdelegate stop(room_id), to: GamesServer
end
