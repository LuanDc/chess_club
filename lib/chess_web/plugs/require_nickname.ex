defmodule ChessWeb.Plugs.RequireNickname do
  @moduledoc """
  Ensures the session has a `:nickname`. If absent, halts the
  connection and redirects to `/`. If present, assigns it to
  `:nickname` so controllers and LiveViews can read it directly.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :nickname) do
      nickname when is_binary(nickname) and byte_size(nickname) > 0 ->
        assign(conn, :nickname, nickname)

      _ ->
        conn
        |> redirect(to: "/")
        |> halt()
    end
  end
end
