defmodule ChessWeb.SessionControllerTest do
  use ChessWeb.ConnCase, async: true

  describe "POST /session" do
    test "stores nickname in session and redirects to /lobby", %{conn: conn} do
      conn = post(conn, ~p"/session", %{"nickname" => "Alice"})

      assert redirected_to(conn) == ~p"/lobby"
      assert get_session(conn, :nickname) == "Alice"
    end

    test "trims whitespace before storing", %{conn: conn} do
      conn = post(conn, ~p"/session", %{"nickname" => "   Bob   "})

      assert redirected_to(conn) == ~p"/lobby"
      assert get_session(conn, :nickname) == "Bob"
    end

    test "redirects back to / with flash error when nickname is too short", %{conn: conn} do
      conn = post(conn, ~p"/session", %{"nickname" => "a"})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "pelo menos 2"
      refute get_session(conn, :nickname)
    end

    test "redirects back to / when nickname is missing", %{conn: conn} do
      conn = post(conn, ~p"/session", %{})

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :nickname)
    end
  end

  describe "DELETE /session" do
    test "clears the nickname and redirects to /", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{nickname: "Alice"})
        |> delete(~p"/session")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :nickname)
    end
  end
end
