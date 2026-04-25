defmodule ChessWeb.LiveAuth do
  @moduledoc """
  LiveView `on_mount` hooks for session-based nickname auth.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:require_nickname, _params, session, socket) do
    case session["nickname"] do
      nickname when is_binary(nickname) and byte_size(nickname) > 0 ->
        {:cont, assign(socket, :nickname, nickname)}

      _ ->
        {:halt, redirect(socket, to: "/")}
    end
  end
end
