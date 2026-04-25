defmodule ChessWeb.Router do
  use ChessWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ChessWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :authenticated do
    plug ChessWeb.Plugs.RequireNickname
  end

  scope "/", ChessWeb do
    pipe_through :browser

    live "/", LoginLive, :index
    post "/session", SessionController, :create
    delete "/session", SessionController, :delete
  end

  scope "/", ChessWeb do
    pipe_through [:browser, :authenticated]

    live_session :authenticated,
      on_mount: [{ChessWeb.LiveAuth, :require_nickname}] do
      live "/lobby", LobbyLive, :index
      live "/games/solo", GameLive, :solo
      live "/games/:room_id", GameLive, :show
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:chess, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ChessWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
