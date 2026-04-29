defmodule Chess.GameSessionTest do
  use ExUnit.Case, async: true

  alias Chess.GameSession

  defp new_multiplayer do
    {:ok, session} = GameSession.new("room-multi", :multiplayer, "Alice", "Bob")
    on_exit(fn -> GameSession.stop(session) end)
    session
  end

  defp new_solo do
    {:ok, session} = GameSession.new("room-solo", :solo, "Alice", "Alice")
    on_exit(fn -> GameSession.stop(session) end)
    session
  end

  describe "new/4" do
    test "returns a session with a live game_pid" do
      {:ok, session} = GameSession.new("r", :multiplayer, "A", "B")
      assert is_pid(session.game_pid)
      assert Process.alive?(session.game_pid)
      GameSession.stop(session)
    end

    test "initial status is :in_progress" do
      {:ok, session} = GameSession.new("r", :multiplayer, "A", "B")
      assert session.game.status == :in_progress
      GameSession.stop(session)
    end
  end

  describe "move/5" do
    test "valid move returns an updated session" do
      session = new_multiplayer()
      assert {:ok, updated} = GameSession.move(session, "Alice", "e2", "e4", nil)
      assert updated.game.side_to_move == :black
      assert [%{from: "e2", to: "e4"}] = updated.game.history
    end

    test "wrong player returns :not_your_turn" do
      session = new_multiplayer()
      assert {:error, :not_your_turn} = GameSession.move(session, "Bob", "e7", "e5", nil)
    end

    test "non-player returns :not_a_player" do
      session = new_multiplayer()
      assert {:error, :not_a_player} = GameSession.move(session, "Mallory", "e2", "e4", nil)
    end

    test "illegal move returns an engine error" do
      session = new_multiplayer()
      assert {:error, _} = GameSession.move(session, "Alice", "e2", "e5", nil)
    end

    test "move on a finished game returns :game_over" do
      session = new_multiplayer()
      # fool's mate
      {:ok, s1} = GameSession.move(session, "Alice", "f2", "f3", nil)
      {:ok, s2} = GameSession.move(s1, "Bob", "e7", "e5", nil)
      {:ok, s3} = GameSession.move(s2, "Alice", "g2", "g4", nil)
      {:ok, s4} = GameSession.move(s3, "Bob", "d8", "h4", nil)
      assert s4.game.status != :in_progress
      assert {:error, :game_over} = GameSession.move(s4, "Alice", "a2", "a3", nil)
    end
  end

  describe "resign/2 — solo" do
    test "ends the game with status :ended" do
      session = new_solo()
      assert {:ok, updated} = GameSession.resign(session, "Alice")
      assert updated.game.status == :ended
    end

    test "non-player cannot resign" do
      session = new_solo()
      assert {:error, :not_a_player} = GameSession.resign(session, "Mallory")
    end

    test "cannot resign an already finished game" do
      session = new_solo()
      {:ok, ended} = GameSession.resign(session, "Alice")
      assert {:error, :game_over} = GameSession.resign(ended, "Alice")
    end
  end

  describe "resign/2 — multiplayer" do
    test "white resigning declares black the winner" do
      session = new_multiplayer()
      assert {:ok, updated} = GameSession.resign(session, "Alice")
      assert match?({:winner, :black, :resign}, updated.game.status)
    end

    test "black resigning declares white the winner" do
      session = new_multiplayer()
      assert {:ok, updated} = GameSession.resign(session, "Bob")
      assert match?({:winner, :white, :resign}, updated.game.status)
    end

    test "non-player cannot resign" do
      session = new_multiplayer()
      assert {:error, :not_a_player} = GameSession.resign(session, "Mallory")
    end
  end

  describe "legal_moves_from/2" do
    test "returns legal target squares for a piece" do
      session = new_multiplayer()
      moves = GameSession.legal_moves_from(session, "e2")
      assert "e4" in moves
      assert "e3" in moves
    end

    test "returns [] for an empty square" do
      session = new_multiplayer()
      assert [] == GameSession.legal_moves_from(session, "e4")
    end
  end

  describe "player?/2" do
    test "registered player returns true" do
      session = new_multiplayer()
      assert GameSession.player?(session, "Alice")
      assert GameSession.player?(session, "Bob")
    end

    test "unknown nickname returns false" do
      session = new_multiplayer()
      refute GameSession.player?(session, "Mallory")
    end
  end

  describe "public_state/1" do
    test "includes all expected keys" do
      session = new_multiplayer()
      state = GameSession.public_state(session)

      assert Map.has_key?(state, :room_id)
      assert Map.has_key?(state, :mode)
      assert Map.has_key?(state, :players)
      assert Map.has_key?(state, :side_to_move)
      assert Map.has_key?(state, :status)
      assert Map.has_key?(state, :history)
      assert Map.has_key?(state, :fen)
      assert is_binary(state.fen)
    end
  end
end
