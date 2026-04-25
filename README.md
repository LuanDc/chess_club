# Chess Club

A real-time multiplayer chess application built with **Phoenix LiveView**. Players pick a nickname, create or join a room from the lobby, and play live games over WebSockets — no accounts, no database, no page reloads.

The chess engine itself is provided by [`binbo`](https://hex.pm/packages/binbo) (an Erlang chess library). Everything else — lobby, rooms, game state, broadcasts — runs in-memory through OTP processes (GenServers, Registry, DynamicSupervisor, PubSub).

---

## Features

- **Nickname-based sessions** — no signup; the nickname is stored in the Plug session cookie.
- **Lobby** — create a room, see open rooms from other players, join with one click.
- **Multiplayer games** — turn-enforced, real-time updates pushed via Phoenix PubSub.
- **Solo mode** — play both sides on a single board (useful for analysis or teaching).
- **Resignation** — multiplayer awards the win to the opponent; solo simply ends the game.
- **Move history & legal-move highlights** rendered live in the LiveView UI.
- **Tailwind + esbuild** asset pipeline, zero front-end JS framework.

---

## Tech stack

| Layer        | Choice                                                   |
| ------------ | -------------------------------------------------------- |
| Language     | Elixir `~> 1.14`                                         |
| Web          | Phoenix `~> 1.7.21` + Phoenix LiveView `~> 1.0`          |
| HTTP server  | Bandit `~> 1.5`                                          |
| Realtime     | `Phoenix.PubSub` (in-process, no Redis)                  |
| Chess engine | `binbo ~> 4.0` (Erlang)                                  |
| Front-end    | Tailwind 3.4, esbuild 0.17, HEEx templates               |
| Testing      | ExUnit, Floki, LazyHTML                                  |

> `phoenix_ecto`, `ecto_sql`, and `postgrex` are present in `mix.exs` for future use, but **the application does not currently start a `Repo` and contains no migrations or schemas.** All state is held in OTP processes (see below). Postgres is **not** required to run the app.

---

## Architecture

### Process tree

Started in [lib/chess/application.ex](lib/chess/application.ex):

```
Chess.Supervisor (one_for_one)
├── ChessWeb.Telemetry
├── DNSCluster
├── Phoenix.PubSub          (name: Chess.PubSub)
├── Finch                   (name: Chess.Finch)
├── Chess.Rooms             (GenServer — lobby state)
├── Registry                (name: Chess.GameRegistry, keys: :unique)
├── DynamicSupervisor       (name: Chess.GameSupervisor)
└── ChessWeb.Endpoint
```

### Request → game flow

1. The user submits a nickname to `POST /session`. [ChessWeb.SessionController](lib/chess_web/controllers/session_controller.ex) trims it and stores it in the session cookie.
2. `LiveAuth` (mount hook) and `RequireNickname` (plug) gate every authenticated route. See [lib/chess_web/live_auth.ex](lib/chess_web/live_auth.ex) and [lib/chess_web/plugs/require_nickname.ex](lib/chess_web/plugs/require_nickname.ex).
3. [LobbyLive](lib/chess_web/live/lobby_live.ex) subscribes to the `"lobby"` PubSub topic and renders rooms from `Chess.Rooms.list/0`. Creating, joining, or cancelling a room broadcasts `{:rooms_changed, rooms}` so every connected client refreshes without polling.
4. When a guest joins a room, the lobby calls [`Chess.Games.start_game/1`](lib/chess/games.ex) which spawns a [`Chess.GameServer`](lib/chess/game_server.ex) under `Chess.GameSupervisor`, registered in `Chess.GameRegistry` keyed by `room_id`. The host receives `{:room_joined, room}` and is navigated into the game.
5. [GameLive](lib/chess_web/live/game_live.ex) subscribes to `"game:<room_id>"`. Each move is sent through `Chess.Games.move/5` → `GameServer` → `Chess.Game` (binbo wrapper). The new state is broadcast to both players.

### Module overview

#### Domain (`lib/chess/`)

| Module             | Responsibility                                                                                                                                              |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`Chess.Game`](lib/chess/game.ex)             | Thin Elixir API around `:binbo`. Owns one binbo server pid; exposes `new/0`, `move/4`, `fen/1`, `status/1`, `legal_moves/1`, `set_winner/3`, etc.            |
| [`Chess.GameServer`](lib/chess/game_server.ex) | GenServer (one per room) that wraps a `Chess.Game`. Enforces turn order, tracks history, normalizes status, and broadcasts `{:game_state, state}` on PubSub. |
| [`Chess.Games`](lib/chess/games.ex)            | Public façade. Resolves a `room_id` to its `GameServer` via `Registry` and delegates calls.                                                                  |
| [`Chess.Rooms`](lib/chess/rooms.ex)            | GenServer holding the in-memory list of open lobby rooms. Auto-prunes rooms older than 10 min on read. Broadcasts `{:rooms_changed, rooms}`.                 |
| [`Chess.Mailer`](lib/chess/mailer.ex)          | Swoosh mailer (`Swoosh.Adapters.Local` in dev, unused in current flows).                                                                                     |

#### Web (`lib/chess_web/`)

| Module / file                                                                          | Responsibility                                                              |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| [`ChessWeb.Router`](lib/chess_web/router.ex)                                           | Routes; gates `/lobby` and `/games/*` behind `RequireNickname` + `LiveAuth`. |
| [`ChessWeb.LoginLive`](lib/chess_web/live/login_live.ex)                               | Nickname form (`/`).                                                         |
| [`ChessWeb.LobbyLive`](lib/chess_web/live/lobby_live.ex)                               | Lobby with create/join/cancel/solo actions.                                  |
| [`ChessWeb.GameLive`](lib/chess_web/live/game_live.ex)                                 | The board UI; mounts in `:solo` or `:show` (multiplayer) action.             |
| [`ChessWeb.SessionController`](lib/chess_web/controllers/session_controller.ex)        | Creates / clears the nickname session.                                       |
| [`ChessWeb.Components.ChessComponents`](lib/chess_web/components/chess_components.ex)  | Board, square, piece, player bar, move history.                              |
| [`ChessWeb.Components.UiComponents`](lib/chess_web/components/ui_components.ex)        | Generic UI (buttons, cards, inputs, navbar, room cards, etc.).               |
| [`ChessWeb.Plugs.RequireNickname`](lib/chess_web/plugs/require_nickname.ex)            | Plug guard for HTTP routes.                                                  |
| [`ChessWeb.LiveAuth`](lib/chess_web/live_auth.ex)                                      | Equivalent guard for `live_session`.                                         |

### Routes

| Method | Path                | Handler                              | Auth |
| ------ | ------------------- | ------------------------------------ | ---- |
| GET    | `/`                 | `LoginLive`                          | —    |
| POST   | `/session`          | `SessionController.create`           | —    |
| DELETE | `/session`          | `SessionController.delete`           | —    |
| LIVE   | `/lobby`            | `LobbyLive`                          | ✅   |
| LIVE   | `/games/solo`       | `GameLive` (`:solo`)                 | ✅   |
| LIVE   | `/games/:room_id`   | `GameLive` (`:show`)                 | ✅   |
| GET    | `/dev/dashboard`    | LiveDashboard *(dev only)*           | —    |
| GET    | `/dev/mailbox`      | Swoosh mailbox preview *(dev only)*  | —    |

### PubSub topics

| Topic                | Message                                  | Producer                  | Consumer            |
| -------------------- | ---------------------------------------- | ------------------------- | ------------------- |
| `"lobby"`            | `{:rooms_changed, rooms}`                | `Chess.Rooms`             | `LobbyLive`         |
| `"lobby"`            | `{:room_joined, room}`                   | `Chess.Rooms` (on join)   | `LobbyLive` (host)  |
| `"game:<room_id>"`   | `{:game_state, public_state}`            | `Chess.GameServer`        | `GameLive` (both)   |

---

## Data model (in-memory)

There is **no database**. The two stateful structs are:

### `Chess.Rooms.Room`

```elixir
%Chess.Rooms.Room{
  id: "A1B2C3",          # 6-char hex, generated server-side
  host: "Alice",         # nickname of the room creator
  guest: "Bob" | nil,    # nickname of the joiner (nil while waiting)
  inserted_at: 1_711_000_000  # unix seconds; rooms expire after 10 min
}
```

Held inside the `Chess.Rooms` GenServer state as a list. **Lost on application restart** — by design.

### `Chess.GameServer.State`

```elixir
%Chess.GameServer.State{
  room_id: "A1B2C3",
  mode: :multiplayer | :solo,
  players: %{white: "Alice", black: "Bob"},
  game_pid: #PID<0.1234.0>,         # underlying binbo server
  side_to_move: :white | :black,
  status: :in_progress
          | {:checkmate, :white_wins | :black_wins}
          | {:draw, atom()}
          | {:winner, :white | :black, term()}
          | :ended,
  history: [%{from: "e2", to: "e4", color: :white, promotion: nil}, ...],
  started_at: 1_711_000_000
}
```

The "public" state pushed to LiveViews is a map without `game_pid`, plus the current `fen`.

### Session

The nickname lives in Plug's signed session cookie under the key `:nickname`. No server-side session store.

---

## Running locally

### Prerequisites

- **Elixir** `~> 1.14` and a matching **Erlang/OTP**. Install via [asdf](https://asdf-vm.com/) or [Homebrew](https://brew.sh/) (`brew install elixir`).
- That's it. **No Postgres, no Redis, no Node** — `esbuild` and `tailwind` are managed by their respective Hex packages.

### Setup

```bash
git clone <this-repo>
cd chess
mix setup         # fetches deps, installs tailwind/esbuild, builds assets
```

### Start the server

```bash
mix phx.server
# or, with an IEx shell attached:
iex -S mix phx.server
```

Then open <http://localhost:4000>.

To play a multiplayer game on a single machine, open the app in **two browser windows** (or one regular + one private) and use a different nickname in each. One creates a room, the other joins.

### Useful dev URLs

- <http://localhost:4000/dev/dashboard> — Phoenix LiveDashboard
- <http://localhost:4000/dev/mailbox> — Swoosh local mailbox

### Tests

```bash
mix test
```

The test suite covers the chess wrapper, lobby/game GenServers, plugs, components, and LiveViews.

### Asset rebuilds

`mix phx.server` runs `esbuild --watch` and `tailwind --watch` automatically (configured in [config/dev.exs](config/dev.exs)). For one-off builds:

```bash
mix assets.build       # dev
mix assets.deploy      # minified + digested for prod
```

---

## Production notes

- Set `SECRET_KEY_BASE` (generate with `mix phx.gen.secret`).
- Set `PHX_HOST` and `PORT` as needed.
- Set `PHX_SERVER=true` when running from a release.
- Because all game state is in-process, a deploy or restart **drops every active game and lobby room**. If you need persistence or multi-node fan-out, you'd add an Ecto repo (deps are already there) and either back the Registry/Rooms with the database or distribute via `:pg` / `Phoenix.PubSub.PG2`.

See `config/runtime.exs` for the full prod configuration template.
