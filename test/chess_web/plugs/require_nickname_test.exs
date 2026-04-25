defmodule ChessWeb.Plugs.RequireNicknameTest do
  use ChessWeb.ConnCase, async: true

  alias ChessWeb.Plugs.RequireNickname

  setup %{conn: conn} do
    {:ok,
     conn:
       conn
       |> Plug.Test.init_test_session(%{})}
  end

  test "halts and redirects to / when no :nickname is in session", %{conn: conn} do
    conn = RequireNickname.call(conn, [])

    assert conn.halted
    assert redirected_to(conn) == "/"
  end

  test "passes the conn through and assigns @nickname when session has it", %{conn: conn} do
    conn =
      conn
      |> put_session(:nickname, "alice")
      |> RequireNickname.call([])

    refute conn.halted
    assert conn.assigns[:nickname] == "alice"
  end
end
