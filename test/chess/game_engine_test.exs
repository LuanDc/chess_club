defmodule Chess.GameEngineTest do
  use ExUnit.Case, async: true

  alias Chess.GameEngine

  describe "new/0" do
    test "starts a new game from initial position" do
      assert {:ok, pid} = GameEngine.new()
      assert is_pid(pid)
      fen = GameEngine.fen(pid)
      assert fen =~ "rnbqkbnr/pppppppp"
      GameEngine.stop(pid)
    end

    test "side_to_move starts with white" do
      {:ok, pid} = GameEngine.new()
      assert GameEngine.side_to_move(pid) == :white
      GameEngine.stop(pid)
    end

    test "status is :in_progress initially" do
      {:ok, pid} = GameEngine.new()
      assert GameEngine.status(pid) == :in_progress
      GameEngine.stop(pid)
    end
  end

  describe "move/3" do
    setup do
      {:ok, pid} = GameEngine.new()
      on_exit(fn -> if Process.alive?(pid), do: GameEngine.stop(pid) end)
      %{pid: pid}
    end

    test "accepts a legal pawn move", %{pid: pid} do
      assert {:ok, status} = GameEngine.move(pid, "e2", "e4")
      assert status == :in_progress
      assert GameEngine.side_to_move(pid) == :black
    end

    test "rejects an illegal move", %{pid: pid} do
      assert {:error, _reason} = GameEngine.move(pid, "e2", "e5")
      assert GameEngine.side_to_move(pid) == :white
    end

    test "rejects moving the wrong color's piece", %{pid: pid} do
      assert {:error, _reason} = GameEngine.move(pid, "e7", "e5")
    end

    test "fool's mate ends in checkmate (black wins)", %{pid: pid} do
      {:ok, _} = GameEngine.move(pid, "f2", "f3")
      {:ok, _} = GameEngine.move(pid, "e7", "e5")
      {:ok, _} = GameEngine.move(pid, "g2", "g4")
      {:ok, status} = GameEngine.move(pid, "d8", "h4")
      assert status == {:checkmate, :black_wins}
      assert GameEngine.status(pid) == {:checkmate, :black_wins}
    end
  end

  describe "legal_moves_from/2" do
    test "returns all legal squares for a piece in initial position" do
      {:ok, pid} = GameEngine.new()
      moves = GameEngine.legal_moves_from(pid, "e2")
      assert "e3" in moves
      assert "e4" in moves
      GameEngine.stop(pid)
    end

    test "returns [] for empty square" do
      {:ok, pid} = GameEngine.new()
      assert GameEngine.legal_moves_from(pid, "e4") == []
      GameEngine.stop(pid)
    end

    test "returns [] for opponent's piece when it's not their turn" do
      {:ok, pid} = GameEngine.new()
      assert GameEngine.legal_moves_from(pid, "e7") == []
      GameEngine.stop(pid)
    end
  end

  describe "set_winner/3" do
    test "marks the game as won by the given color (resign)" do
      {:ok, pid} = GameEngine.new()
      assert :ok = GameEngine.set_winner(pid, :white, :resign)

      status = GameEngine.status(pid)

      assert match?({:winner, :white, _}, status) or
               status == {:winner, :white_wins}

      GameEngine.stop(pid)
    end
  end

  describe "pieces/1" do
    test "returns map of square -> {color, piece} for the initial position" do
      {:ok, pid} = GameEngine.new()
      pieces = GameEngine.pieces(pid)

      assert pieces["e1"] == {:white, :king}
      assert pieces["e8"] == {:black, :king}
      assert pieces["a1"] == {:white, :rook}
      assert pieces["d2"] == {:white, :pawn}
      refute Map.has_key?(pieces, "e4")

      GameEngine.stop(pid)
    end
  end
end
