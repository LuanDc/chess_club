defmodule Chess.GameTest do
  use ExUnit.Case, async: true

  alias Chess.Game

  describe "new/0" do
    test "starts a new game from initial position" do
      assert {:ok, pid} = Game.new()
      assert is_pid(pid)
      fen = Game.fen(pid)
      assert fen =~ "rnbqkbnr/pppppppp"
      Game.stop(pid)
    end

    test "side_to_move starts with white" do
      {:ok, pid} = Game.new()
      assert Game.side_to_move(pid) == :white
      Game.stop(pid)
    end

    test "status is :in_progress initially" do
      {:ok, pid} = Game.new()
      assert Game.status(pid) == :in_progress
      Game.stop(pid)
    end
  end

  describe "move/3" do
    setup do
      {:ok, pid} = Game.new()
      on_exit(fn -> if Process.alive?(pid), do: Game.stop(pid) end)
      %{pid: pid}
    end

    test "accepts a legal pawn move", %{pid: pid} do
      assert {:ok, status} = Game.move(pid, "e2", "e4")
      assert status == :in_progress
      assert Game.side_to_move(pid) == :black
    end

    test "rejects an illegal move", %{pid: pid} do
      assert {:error, _reason} = Game.move(pid, "e2", "e5")
      assert Game.side_to_move(pid) == :white
    end

    test "rejects moving the wrong color's piece", %{pid: pid} do
      assert {:error, _reason} = Game.move(pid, "e7", "e5")
    end

    test "fool's mate ends in checkmate (black wins)", %{pid: pid} do
      {:ok, _} = Game.move(pid, "f2", "f3")
      {:ok, _} = Game.move(pid, "e7", "e5")
      {:ok, _} = Game.move(pid, "g2", "g4")
      {:ok, status} = Game.move(pid, "d8", "h4")
      assert status == {:checkmate, :black_wins}
      assert Game.status(pid) == {:checkmate, :black_wins}
    end
  end

  describe "legal_moves_from/2" do
    test "returns all legal squares for a piece in initial position" do
      {:ok, pid} = Game.new()
      moves = Game.legal_moves_from(pid, "e2")
      assert "e3" in moves
      assert "e4" in moves
      Game.stop(pid)
    end

    test "returns [] for empty square" do
      {:ok, pid} = Game.new()
      assert Game.legal_moves_from(pid, "e4") == []
      Game.stop(pid)
    end

    test "returns [] for opponent's piece when it's not their turn" do
      {:ok, pid} = Game.new()
      assert Game.legal_moves_from(pid, "e7") == []
      Game.stop(pid)
    end
  end

  describe "set_winner/3" do
    test "marks the game as won by the given color (resign)" do
      {:ok, pid} = Game.new()
      assert :ok = Game.set_winner(pid, :white, :resign)

      status = Game.status(pid)

      assert match?({:winner, :white, _}, status) or
               status == {:winner, :white_wins}

      Game.stop(pid)
    end
  end

  describe "pieces/1" do
    test "returns map of square -> {color, piece} for the initial position" do
      {:ok, pid} = Game.new()
      pieces = Game.pieces(pid)

      assert pieces["e1"] == {:white, :king}
      assert pieces["e8"] == {:black, :king}
      assert pieces["a1"] == {:white, :rook}
      assert pieces["d2"] == {:white, :pawn}
      refute Map.has_key?(pieces, "e4")

      Game.stop(pid)
    end
  end
end
