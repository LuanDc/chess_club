defmodule ChessWeb.GameLiveTest do
  use ChessWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chess.{Games, Rooms}

  setup %{conn: conn} do
    Rooms.clear()
    on_exit(fn -> Rooms.clear() end)
    {:ok, conn: Plug.Test.init_test_session(conn, %{nickname: "Alice"})}
  end

  defp start_multiplayer_game(white \\ "Alice", black \\ "Bob") do
    room_id = "R-#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      Games.start_game(%{room_id: room_id, mode: :multiplayer, white: white, black: black})

    on_exit(fn -> Games.stop(room_id) end)
    room_id
  end

  describe "/games/:room_id" do
    test "redirects to /lobby when the game does not exist", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/lobby"}}} = live(conn, ~p"/games/MISSING")
    end

    test "redirects to / when not authenticated" do
      room_id = start_multiplayer_game()
      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), ~p"/games/#{room_id}")
    end

    test "renders the chess board with initial position", %{conn: conn} do
      room_id = start_multiplayer_game()
      {:ok, _view, html} = live(conn, ~p"/games/#{room_id}")

      assert html =~ "Chess Club"
      assert html =~ "Alice"
      assert html =~ "Bob"
      # All 16 starting pawns + pieces — at least the kings glyphs
      assert html =~ "♔"
      assert html =~ "♚"
    end

    test "white player sees themselves at the bottom (orientation = white)", %{conn: conn} do
      room_id = start_multiplayer_game()
      {:ok, _view, html} = live(conn, ~p"/games/#{room_id}")

      first_square = first_square(html)
      assert first_square == "a8"
    end

    test "black player sees the board flipped" do
      room_id = start_multiplayer_game("Alice", "Bob")
      bob_conn = build_conn() |> Plug.Test.init_test_session(%{nickname: "Bob"})

      {:ok, _view, html} = live(bob_conn, ~p"/games/#{room_id}")

      assert first_square(html) == "h1"
    end

    test "clicking own piece selects it and highlights legal targets", %{conn: conn} do
      room_id = start_multiplayer_game()
      {:ok, view, _html} = live(conn, ~p"/games/#{room_id}")

      html =
        view
        |> element(~s(button[phx-value-square="e2"]))
        |> render_click()

      assert html =~ ~s(data-selected="true")
      assert html =~ ~s(data-square="e3")
      # legal targets get data-target
      assert html =~ ~s(data-target="true")
    end

    test "clicking a legal target plays the move", %{conn: conn} do
      room_id = start_multiplayer_game()
      {:ok, view, _} = live(conn, ~p"/games/#{room_id}")

      view |> element(~s(button[phx-value-square="e2"])) |> render_click()
      _html = view |> element(~s(button[phx-value-square="e4"])) |> render_click()

      state = Games.get_state(room_id)
      assert state.side_to_move == :black
      assert [%{from: "e2", to: "e4"}] = state.history
    end

    test "clicking opponent piece does nothing when it's not your turn", %{conn: conn} do
      room_id = start_multiplayer_game()
      {:ok, view, _} = live(conn, ~p"/games/#{room_id}")

      html = view |> element(~s(button[phx-value-square="e7"])) |> render_click()
      refute html =~ ~s(data-selected="true")
    end

    test "clicking the same square again deselects", %{conn: conn} do
      room_id = start_multiplayer_game()
      {:ok, view, _} = live(conn, ~p"/games/#{room_id}")

      view |> element(~s(button[phx-value-square="e2"])) |> render_click()
      html = view |> element(~s(button[phx-value-square="e2"])) |> render_click()

      refute html =~ ~s(data-selected="true")
    end

    test "opponent sees the move via PubSub without clicking", %{conn: alice_conn} do
      room_id = start_multiplayer_game()
      bob_conn = build_conn() |> Plug.Test.init_test_session(%{nickname: "Bob"})

      {:ok, alice_view, _} = live(alice_conn, ~p"/games/#{room_id}")
      {:ok, bob_view, _} = live(bob_conn, ~p"/games/#{room_id}")

      alice_view |> element(~s(button[phx-value-square="e2"])) |> render_click()
      alice_view |> element(~s(button[phx-value-square="e4"])) |> render_click()

      bob_html = render(bob_view)
      assert bob_html =~ "e2-e4"
    end

    test "move history shows pairs in the sidebar", %{conn: conn} do
      room_id = start_multiplayer_game()
      {:ok, view, _} = live(conn, ~p"/games/#{room_id}")

      view |> element(~s(button[phx-value-square="e2"])) |> render_click()
      html = view |> element(~s(button[phx-value-square="e4"])) |> render_click()

      assert html =~ "e2-e4"
      assert html =~ "Movimentos · 1"
    end

    test "clicking 'Desistir' ends the game and shows game-over card", %{conn: conn} do
      room_id = start_multiplayer_game()
      {:ok, view, _} = live(conn, ~p"/games/#{room_id}")

      html =
        view
        |> element("button", "Desistir")
        |> render_click()

      assert html =~ "Fim de Jogo"
      assert html =~ "Voltar ao Lobby"
    end

    test "opponent sees game-over message after resign via PubSub" do
      room_id = start_multiplayer_game()
      alice_conn = build_conn() |> Plug.Test.init_test_session(%{nickname: "Alice"})
      bob_conn = build_conn() |> Plug.Test.init_test_session(%{nickname: "Bob"})

      {:ok, alice_view, _} = live(alice_conn, ~p"/games/#{room_id}")
      {:ok, bob_view, _} = live(bob_conn, ~p"/games/#{room_id}")

      alice_view |> element("button", "Desistir") |> render_click()

      bob_html = render(bob_view)
      assert bob_html =~ "Alice desistiu"
      assert bob_html =~ "Você venceu"
    end

    test "opponent sees game-over when player's LiveView dies (auto-resign)" do
      Process.flag(:trap_exit, true)
      room_id = start_multiplayer_game()
      alice_conn = build_conn() |> Plug.Test.init_test_session(%{nickname: "Alice"})
      bob_conn = build_conn() |> Plug.Test.init_test_session(%{nickname: "Bob"})

      {:ok, alice_view, _} = live(alice_conn, ~p"/games/#{room_id}")
      {:ok, bob_view, _} = live(bob_conn, ~p"/games/#{room_id}")

      Process.exit(alice_view.pid, :kill)
      Process.sleep(100)

      bob_html = render(bob_view)
      assert bob_html =~ "Alice desistiu"
      assert bob_html =~ "Você venceu"
    end

    test "'Voltar ao Lobby' navigates to /lobby", %{conn: conn} do
      room_id = start_multiplayer_game()
      {:ok, view, _} = live(conn, ~p"/games/#{room_id}")

      view |> element("button", "Desistir") |> render_click()

      assert {:error, {:live_redirect, %{to: "/lobby"}}} =
               view |> element("a, button", "Voltar ao Lobby") |> render_click()
    end
  end

  describe "/games/solo" do
    test "starts a fresh solo game and renders the board", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/games/solo")

      assert html =~ "Chess Club"
      assert html =~ "Modo solo"
      assert html =~ "♔"

      view |> element(~s(button[phx-value-square="e2"])) |> render_click()
      html = view |> element(~s(button[phx-value-square="e4"])) |> render_click()

      # After playing white's e2-e4, the e2 square is now empty in render
      refute html =~ ~s(data-square="e2"\sclass=".*♙)
    end

    test "solo player can move both colors in turn", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/games/solo")

      view |> element(~s(button[phx-value-square="e2"])) |> render_click()
      view |> element(~s(button[phx-value-square="e4"])) |> render_click()

      view |> element(~s(button[phx-value-square="e7"])) |> render_click()
      html = view |> element(~s(button[phx-value-square="e5"])) |> render_click()

      # Both pawns now off their starting squares
      refute html =~ ~s(data-square="e2".+♙)
      refute html =~ ~s(data-square="e7".+♟)
    end

    test "solo resign button is labelled 'Encerrar Partida'", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/games/solo")
      assert html =~ "Encerrar Partida"

      html = view |> element("button", "Encerrar Partida") |> render_click()
      assert html =~ "Fim de Jogo"
    end
  end

  defp first_square(html) do
    Regex.run(~r/data-square="([a-h][1-8])"/, html, capture: :all_but_first)
    |> List.first()
  end
end
