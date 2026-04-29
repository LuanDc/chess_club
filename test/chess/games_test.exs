defmodule Chess.GamesTest do
  use ExUnit.Case, async: true

  alias Chess.Game
  alias Chess.Games

  @mp_players %{white: "Alice", black: "Bob"}
  @solo_players %{white: "Alice", black: "Alice"}

  ## new/4

  describe "new/4" do
    test "creates a Game with correct players" do
      game = Games.new("room-1", :multiplayer, "Alice", "Bob")
      assert game.players == @mp_players
    end

    test "sets room_id and mode" do
      game = Games.new("room-1", :solo, "Alice", "Alice")
      assert game.room_id == "room-1"
      assert game.mode == :solo
    end

    test "starts with side_to_move :white" do
      game = Games.new("room-1", :multiplayer, "Alice", "Bob")
      assert game.side_to_move == :white
    end

    test "starts with status :in_progress and empty history" do
      game = Games.new("room-1", :multiplayer, "Alice", "Bob")
      assert game.status == :in_progress
      assert game.history == []
    end
  end

  ## apply_move/4

  describe "apply_move/4" do
    setup do
      {:ok, game: Games.new("room-1", :multiplayer, "Alice", "Bob")}
    end

    test "appends move record to history", %{game: game} do
      move = %{from: "e2", to: "e4", color: :white, promotion: nil}
      result = Games.apply_move(game, move, :in_progress, :black)
      assert result.history == [move]
    end

    test "updates status", %{game: game} do
      move = %{from: "d8", to: "h4", color: :black, promotion: nil}
      result = Games.apply_move(game, move, {:checkmate, :black_wins}, :white)
      assert result.status == {:checkmate, :black_wins}
    end

    test "updates side_to_move", %{game: game} do
      move = %{from: "e2", to: "e4", color: :white, promotion: nil}
      result = Games.apply_move(game, move, :in_progress, :black)
      assert result.side_to_move == :black
    end

    test "preserves other fields", %{game: game} do
      move = %{from: "e2", to: "e4", color: :white, promotion: nil}
      result = Games.apply_move(game, move, :in_progress, :black)
      assert result.room_id == game.room_id
      assert result.mode == game.mode
      assert result.players == game.players
    end
  end

  ## apply_solo_resign/1

  describe "apply_solo_resign/1" do
    test "sets status to :ended" do
      game = Games.new("room-1", :solo, "Alice", "Alice")
      result = Games.apply_solo_resign(game)
      assert result.status == :ended
    end

    test "does not modify other fields" do
      game = Games.new("room-1", :solo, "Alice", "Alice")
      result = Games.apply_solo_resign(game)
      assert result.room_id == game.room_id
      assert result.players == game.players
      assert result.history == game.history
    end
  end

  ## apply_multiplayer_resign/2

  describe "apply_multiplayer_resign/2" do
    test "white resigning returns black as winner" do
      game = %Game{room_id: "r", mode: :multiplayer, players: @mp_players}
      assert {:ok, new_game, :black} = Games.apply_multiplayer_resign(game, "Alice")
      assert new_game.status == {:winner, :black, :resign}
    end

    test "black resigning returns white as winner" do
      game = %Game{room_id: "r", mode: :multiplayer, players: @mp_players}
      assert {:ok, new_game, :white} = Games.apply_multiplayer_resign(game, "Bob")
      assert new_game.status == {:winner, :white, :resign}
    end

    test "returns error when game is already over" do
      game = %Game{
        room_id: "r",
        mode: :multiplayer,
        players: @mp_players,
        status: {:winner, :white, :resign}
      }

      assert {:error, :game_over} = Games.apply_multiplayer_resign(game, "Alice")
    end

    test "returns error for unknown nickname" do
      game = %Game{room_id: "r", mode: :multiplayer, players: @mp_players}
      assert {:error, :not_a_player} = Games.apply_multiplayer_resign(game, "Mallory")
    end

    test "returns error in solo mode" do
      game = %Game{room_id: "r", mode: :solo, players: @solo_players}
      assert {:error, :solo_mode} = Games.apply_multiplayer_resign(game, "Alice")
    end
  end

  ## ensure_in_progress/1

  describe "ensure_in_progress/1" do
    test "ok when :in_progress" do
      assert :ok = Games.ensure_in_progress(:in_progress)
    end

    test "error for :ended" do
      assert {:error, :game_over} = Games.ensure_in_progress(:ended)
    end

    test "error for checkmate tuple" do
      assert {:error, :game_over} = Games.ensure_in_progress({:checkmate, :black_wins})
    end

    test "error for winner tuple" do
      assert {:error, :game_over} = Games.ensure_in_progress({:winner, :white, :resign})
    end
  end

  ## color_for/3

  describe "color_for/3 (multiplayer)" do
    test "white player" do
      assert {:ok, :white} = Games.color_for(:multiplayer, @mp_players, "Alice")
    end

    test "black player" do
      assert {:ok, :black} = Games.color_for(:multiplayer, @mp_players, "Bob")
    end

    test "unknown nickname" do
      assert {:error, :not_a_player} = Games.color_for(:multiplayer, @mp_players, "Mallory")
    end
  end

  describe "color_for/3 (solo)" do
    test "single player returns :solo" do
      assert {:ok, :solo} = Games.color_for(:solo, @solo_players, "Alice")
    end

    test "unknown nickname in solo returns :not_a_player" do
      assert {:error, :not_a_player} = Games.color_for(:solo, @solo_players, "Mallory")
    end
  end

  ## ensure_turn_for/4

  describe "ensure_turn_for/4 (multiplayer)" do
    test "ok when correct player" do
      assert :ok = Games.ensure_turn_for(:multiplayer, @mp_players, :white, "Alice")
    end

    test "error when wrong player" do
      assert {:error, :not_your_turn} =
               Games.ensure_turn_for(:multiplayer, @mp_players, :white, "Bob")
    end

    test "ok for black on black's turn" do
      assert :ok = Games.ensure_turn_for(:multiplayer, @mp_players, :black, "Bob")
    end

    test "error for unknown nickname" do
      assert {:error, :not_your_turn} =
               Games.ensure_turn_for(:multiplayer, @mp_players, :white, "Mallory")
    end
  end

  describe "ensure_turn_for/4 (solo)" do
    test "always ok regardless of side_to_move" do
      assert :ok = Games.ensure_turn_for(:solo, @solo_players, :white, "Alice")
      assert :ok = Games.ensure_turn_for(:solo, @solo_players, :black, "Alice")
    end
  end

  ## other_color/1

  describe "other_color/1" do
    test "white -> black" do
      assert :black = Games.other_color(:white)
    end

    test "black -> white" do
      assert :white = Games.other_color(:black)
    end

    test "is its own inverse" do
      assert :white = Games.other_color(Games.other_color(:white))
    end
  end
end
