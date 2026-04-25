defmodule ChessWeb.LoginLiveTest do
  use ChessWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders login form with brand title and nickname input", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Chess Club"
    assert html =~ "Seu apelido"
    assert html =~ ~s(action="/session")
    assert html =~ ~s(method="post")
  end

  test "shows error when nickname has fewer than 2 characters on validate", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#login-form", %{"nickname" => "a"})
      |> render_change()

    assert html =~ "pelo menos 2"
    assert html =~ ~s(disabled)
  end

  test "removes error and enables the button when nickname is valid", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("#login-form", %{"nickname" => "Alice"})
      |> render_change()

    refute html =~ "pelo menos 2"
    refute html =~ ~s(disabled="disabled")
    refute html =~ ~s(disabled\n)
  end

  test "redirects authenticated user to /lobby", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{nickname: "Alice"})

    assert {:error, {:live_redirect, %{to: "/lobby"}}} = live(conn, ~p"/")
  end
end
