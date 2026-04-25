defmodule ChessWeb.LobbyLiveTest do
  use ChessWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chess.Rooms

  setup %{conn: conn} do
    Rooms.clear()
    on_exit(fn -> Rooms.clear() end)
    {:ok, conn: Plug.Test.init_test_session(conn, %{nickname: "Alice"})}
  end

  test "redirects to / when not authenticated", %{conn: _conn} do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/lobby")
  end

  test "renders welcome with nickname, create button and empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/lobby")

    assert html =~ "Bem-vindo"
    assert html =~ "Alice"
    assert html =~ "Criar Sala"
    assert html =~ "Nenhuma sala disponível"
    assert html =~ "Jogar Sozinho"
    assert html =~ "Sair"
  end

  test "clicking 'Criar Sala' creates a room and shows 'Sua sala'", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lobby")

    html =
      view
      |> element("button", "Criar Sala")
      |> render_click()

    assert html =~ "Sua sala"
    assert html =~ "Cancelar Sala"
    refute html =~ "Criar Sala"
  end

  test "another LV connected to /lobby sees rooms appear via PubSub", %{conn: conn} do
    {:ok, observer_view, _} = live(conn, ~p"/lobby")
    refute render(observer_view) =~ "Bob"

    bob_conn = build_conn() |> Plug.Test.init_test_session(%{nickname: "Bob"})
    {:ok, bob_view, _} = live(bob_conn, ~p"/lobby")
    bob_view |> element("button", "Criar Sala") |> render_click()

    # Observer (Alice) should now see Bob's room
    html = render(observer_view)
    assert html =~ "Bob"
    assert html =~ "Entrar"
  end

  test "clicking 'Cancelar Sala' removes the room", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/lobby")
    view |> element("button", "Criar Sala") |> render_click()

    html = view |> element("button", "Cancelar Sala") |> render_click()

    assert html =~ "Criar Sala"
    refute html =~ "Sua sala"
  end

  test "clicking 'Entrar' on another room navigates to /games/:room_id", %{conn: conn} do
    {:ok, _r} = Rooms.create("Bob")

    {:ok, view, _} = live(conn, ~p"/lobby")

    [room] = Rooms.list()

    assert {:error, {:live_redirect, %{to: path}}} =
             view
             |> element(~s(button[phx-value-room-id="#{room.id}"]))
             |> render_click()

    assert path == "/games/#{room.id}"
  end

  test "clicking 'Jogar Sozinho' navigates to /games/solo", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/lobby")

    assert {:error, {:live_redirect, %{to: "/games/solo"}}} =
             view
             |> element("button", "Jogar Sozinho")
             |> render_click()
  end
end
