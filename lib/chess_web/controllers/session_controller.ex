defmodule ChessWeb.SessionController do
  use ChessWeb, :controller

  @min_length 2
  @max_length 20

  def create(conn, params) do
    nickname =
      params
      |> Map.get("nickname", "")
      |> to_string()
      |> String.trim()
      |> String.slice(0, @max_length)

    if String.length(nickname) >= @min_length do
      conn
      |> put_session(:nickname, nickname)
      |> redirect(to: ~p"/lobby")
    else
      conn
      |> put_flash(:error, "Use pelo menos #{@min_length} caracteres.")
      |> redirect(to: ~p"/")
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> configure_session(renew: true)
    |> redirect(to: ~p"/")
  end
end
