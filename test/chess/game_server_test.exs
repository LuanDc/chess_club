defmodule Chess.GameServerTest do
  use ExUnit.Case, async: true

  alias Chess.Games

  defp unique_room_id, do: "T-#{System.unique_integer([:positive])}"

  defp spawn_player, do: spawn(fn -> Process.sleep(:infinity) end)

  defp start_game(opts \\ []) do
    room_id = Keyword.get_lazy(opts, :room_id, &unique_room_id/0)
    white = Keyword.get(opts, :white, "Alice")
    black = Keyword.get(opts, :black, "Bob")
    mode = Keyword.get(opts, :mode, :multiplayer)

    {:ok, _pid} =
      Games.start_game(%{
        room_id: room_id,
        mode: mode,
        white: white,
        black: black
      })

    Phoenix.PubSub.subscribe(Chess.PubSub, "game:#{room_id}")

    on_exit(fn -> cleanup_game(room_id) end)

    %{room_id: room_id, white: white, black: black}
  end

  defp cleanup_game(room_id) do
    case Games.lookup(room_id) do
      {:ok, pid} -> if Process.alive?(pid), do: GenServer.stop(pid)
      _ -> :ok
    end
  end

  describe "start_game/1" do
    test "starts a game registered under room_id" do
      %{room_id: room_id, white: white, black: black} = start_game()

      assert {:ok, pid} = Games.lookup(room_id)
      assert is_pid(pid)

      state = Games.get_state(room_id)
      assert state.room_id == room_id
      assert state.players.white == white
      assert state.players.black == black
      assert state.status == :in_progress
      assert state.history == []
      assert state.side_to_move == :white
    end

    test "refuses to start two games with the same room_id" do
      room_id = unique_room_id()
      {:ok, _} = Games.start_game(%{room_id: room_id, mode: :multiplayer, white: "A", black: "B"})

      assert {:error, _} =
               Games.start_game(%{room_id: room_id, mode: :multiplayer, white: "A", black: "B"})
    end
  end

  describe "move/4 (multiplayer)" do
    test "white can move on the first turn" do
      %{room_id: room_id} = start_game()
      assert {:ok, state} = Games.move(room_id, "Alice", "e2", "e4")
      assert state.side_to_move == :black
      assert [%{from: "e2", to: "e4", color: :white}] = state.history
    end

    test "black cannot move first" do
      %{room_id: room_id} = start_game()
      assert {:error, :not_your_turn} = Games.move(room_id, "Bob", "e7", "e5")
    end

    test "non-player cannot move" do
      %{room_id: room_id} = start_game()
      assert {:error, :not_a_player} = Games.move(room_id, "Mallory", "e2", "e4")
    end

    test "rejects illegal moves" do
      %{room_id: room_id} = start_game()
      assert {:error, _reason} = Games.move(room_id, "Alice", "e2", "e5")
    end

    test "broadcasts :game_state on success" do
      %{room_id: room_id} = start_game()
      {:ok, _state} = Games.move(room_id, "Alice", "e2", "e4")
      assert_receive {:game_state, %{side_to_move: :black, history: [_]}}
    end

    test "does not broadcast on a rejected move" do
      %{room_id: room_id} = start_game()
      {:error, _} = Games.move(room_id, "Alice", "e2", "e5")
      refute_receive {:game_state, _}, 50
    end

    test "rejects move when game is over" do
      %{room_id: room_id} = start_game()
      {:ok, _} = Games.move(room_id, "Alice", "f2", "f3")
      {:ok, _} = Games.move(room_id, "Bob", "e7", "e5")
      {:ok, _} = Games.move(room_id, "Alice", "g2", "g4")
      {:ok, state} = Games.move(room_id, "Bob", "d8", "h4")
      assert state.status == {:checkmate, :black_wins}

      assert {:error, :game_over} = Games.move(room_id, "Alice", "a2", "a3")
    end
  end

  describe "resign/2 (multiplayer)" do
    test "white resigning makes black the winner" do
      %{room_id: room_id} = start_game()
      assert {:ok, state} = Games.resign(room_id, "Alice")
      assert match?({:winner, :black, :resign}, state.status)
    end

    test "broadcasts state after resign" do
      %{room_id: room_id} = start_game()
      {:ok, _} = Games.resign(room_id, "Bob")
      assert_receive {:game_state, %{status: {:winner, :white, :resign}}}
    end

    test "non-player cannot resign" do
      %{room_id: room_id} = start_game()
      assert {:error, :not_a_player} = Games.resign(room_id, "Mallory")
    end
  end

  describe "solo mode" do
    test "single player can move both sides" do
      %{room_id: room_id} = start_game(mode: :solo, white: "Alice", black: "Alice")

      {:ok, state1} = Games.move(room_id, "Alice", "e2", "e4")
      assert state1.side_to_move == :black

      {:ok, state2} = Games.move(room_id, "Alice", "e7", "e5")
      assert state2.side_to_move == :white
    end

    test "resign in solo ends the game without picking a winner" do
      %{room_id: room_id} = start_game(mode: :solo, white: "Alice", black: "Alice")
      assert {:ok, state} = Games.resign(room_id, "Alice")
      assert state.status == :ended
    end
  end

  describe "auto-resign on disconnect" do
    test "DOWN of multiplayer player triggers resign" do
      %{room_id: room_id} = start_game()
      pid = spawn_player()
      :ok = Games.join(room_id, pid, "Alice")

      Process.exit(pid, :kill)
      assert_receive {:game_state, %{status: {:winner, :black, :resign}}}, 200
    end

    test "reconnect within grace cancels auto-resign" do
      previous = Application.get_env(:chess, :resign_grace_ms)
      Application.put_env(:chess, :resign_grace_ms, 100)
      on_exit(fn -> Application.put_env(:chess, :resign_grace_ms, previous) end)

      %{room_id: room_id} = start_game()
      pid1 = spawn_player()
      :ok = Games.join(room_id, pid1, "Alice")

      Process.exit(pid1, :kill)
      Process.sleep(20)

      pid2 = spawn_player()
      :ok = Games.join(room_id, pid2, "Alice")

      refute_receive {:game_state, %{status: {:winner, _, _}}}, 200
    end

    test "DOWN of solo player does not resign" do
      %{room_id: room_id} = start_game(mode: :solo, white: "Alice", black: "Alice")
      pid = spawn_player()
      :ok = Games.join(room_id, pid, "Alice")

      Process.exit(pid, :kill)
      refute_receive {:game_state, _}, 50
    end

    test "DOWN of one tab when player has two does not resign" do
      %{room_id: room_id} = start_game()
      pid1 = spawn_player()
      pid2 = spawn_player()
      :ok = Games.join(room_id, pid1, "Alice")
      :ok = Games.join(room_id, pid2, "Alice")

      Process.exit(pid1, :kill)
      refute_receive {:game_state, _}, 50

      Process.exit(pid2, :kill)
      assert_receive {:game_state, %{status: {:winner, :black, :resign}}}, 200
    end

    test "DOWN of non-player pid is ignored" do
      %{room_id: room_id} = start_game()
      pid = spawn_player()
      :ok = Games.join(room_id, pid, "Mallory")

      Process.exit(pid, :kill)
      refute_receive {:game_state, _}, 50
    end

    test "DOWN after manual resign is no-op" do
      %{room_id: room_id} = start_game()
      pid = spawn_player()
      :ok = Games.join(room_id, pid, "Alice")

      {:ok, _} = Games.resign(room_id, "Alice")
      assert_receive {:game_state, %{status: {:winner, :black, :resign}}}

      Process.exit(pid, :kill)
      refute_receive {:game_state, _}, 50
    end
  end
end
