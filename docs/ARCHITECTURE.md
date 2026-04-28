# Chess — Match Supervision Architecture

This document describes the OTP supervision tree of the chess application,
focused on **the processes that create and run a chess match**: the lobby,
the per-game server, and the registry/supervisor pair that hosts them.

It is intentionally narrow. The Phoenix scaffolding (`ChessWeb.Endpoint`,
`ChessWeb.Telemetry`, `DNSCluster`, `Finch`) is part of the same root
supervisor but not described here. `Phoenix.PubSub` is mentioned only as
the message bus chess processes use.

---

## 1. Supervision tree

The root supervisor is started in
[lib/chess/application.ex:9-25](../lib/chess/application.ex#L9-L25)
with strategy `:one_for_one`. Children are started in the order below,
which matters: the registry and the dynamic supervisor must exist before
any `GameServer` can be spawned.

```
Chess.Supervisor                               [strategy: :one_for_one]
│
├── Chess.Rooms                                GenServer, named, lobby state
│
├── Chess.GameRegistry                         Registry (keys: :unique)
│                                              maps room_id -> GameServer pid
│
├── Chess.GameSupervisor                       DynamicSupervisor (:one_for_one)
│   │                                          owns one child per active match
│   ├── Chess.GameServer  (room "ABC123")  ─┐
│   ├── Chess.GameServer  (room "XYZ789")   │  GenServer, restart: :transient
│   └── ...                                 │  each owns a binbo engine pid
│                                           ─┘
└── (Phoenix infra — out of scope)
        ChessWeb.Telemetry, DNSCluster,
        Phoenix.PubSub, Finch, ChessWeb.Endpoint
```

Two important facts about this shape:

1. **Matches are dynamic.** They are not declared in `application.ex`.
   They are created at runtime by `Chess.Games.start_game/1`
   ([lib/chess/games.ex:18-20](../lib/chess/games.ex#L18-L20)) and live
   under `Chess.GameSupervisor`.
2. **Matches are addressed by `room_id`, not by pid.** Every
   `GameServer` registers itself in `Chess.GameRegistry` via
   `{:via, Registry, {Chess.GameRegistry, room_id}}`
   ([lib/chess/game_server.ex:49](../lib/chess/game_server.ex#L49)),
   so the rest of the system never has to track pids.

---

## 2. Process responsibilities

### 2.1 `Chess.Rooms` — the lobby

- **File:** [lib/chess/rooms.ex](../lib/chess/rooms.ex)
- **Type:** `GenServer`, registered as `Chess.Rooms`
  ([lib/chess/rooms.ex:34-37](../lib/chess/rooms.ex#L34-L37))
- **Started by:** root supervisor as `Chess.Rooms`
  ([lib/chess/application.ex:15](../lib/chess/application.ex#L15))
- **State:** an in-memory list of `%Chess.Rooms.Room{}` structs
  ([lib/chess/rooms.ex:20-30](../lib/chess/rooms.ex#L20-L30)) plus the
  PubSub config it broadcasts on
  ([lib/chess/rooms.ex:65-73](../lib/chess/rooms.ex#L65-L73)).
- **Responsibility:** hold the list of *open* rooms (a host has created a
  room and is waiting for a guest). Rooms older than 10 minutes are
  pruned lazily on every read
  ([lib/chess/rooms.ex:18](../lib/chess/rooms.ex#L18),
  [lib/chess/rooms.ex:162-173](../lib/chess/rooms.ex#L162-L173)).
- **Public API:** `create/1`, `list/0`, `find/1`, `cancel/2`, `join/2`.
- **Broadcasts:** every state-changing call publishes
  `{:rooms_changed, rooms}` on the `"lobby"` topic
  ([lib/chess/rooms.ex:175-177](../lib/chess/rooms.ex#L175-L177)). A
  successful `join` additionally publishes `{:room_joined, room}` so the
  host's LiveView can navigate to the game
  ([lib/chess/rooms.ex:179-181](../lib/chess/rooms.ex#L179-L181)).
- **Persistence:** none. Restarting the BEAM clears the lobby.

The lobby is **not** where matches live. Once two players are paired,
the room is removed from `Chess.Rooms` and a `Chess.GameServer` is
started under `Chess.GameSupervisor`.

### 2.2 `Chess.GameRegistry` — match lookup

- **Type:** `Registry` with `keys: :unique`
- **Started by:**
  [lib/chess/application.ex:16](../lib/chess/application.ex#L16)
- **Responsibility:** map a `room_id` to the pid of the `GameServer`
  running that match.
- **Why it exists:** so any LiveView (or test, or IEx session) can
  address a match by its public `room_id` without ever holding a pid.
  Pids are an implementation detail; `room_id` is the contract.
- **Used by:**
  - `Chess.GameServer.via/1` to register itself
    ([lib/chess/game_server.ex:49](../lib/chess/game_server.ex#L49))
  - `Chess.Games.lookup/1` to resolve a `room_id` to a pid
    ([lib/chess/games.ex:22-27](../lib/chess/games.ex#L22-L27))

### 2.3 `Chess.GameSupervisor` — per-match host

- **Type:** `DynamicSupervisor`, strategy `:one_for_one`
- **Started by:**
  [lib/chess/application.ex:17](../lib/chess/application.ex#L17)
- **Responsibility:** start, isolate, and stop `GameServer` children at
  runtime. One child per active match.
- **Used by:**
  - `Chess.Games.start_game/1` to spawn a new match
    ([lib/chess/games.ex:18-20](../lib/chess/games.ex#L18-L20))
  - `Chess.Games.stop/1` to terminate one
    ([lib/chess/games.ex:38-43](../lib/chess/games.ex#L38-L43))
- **Isolation:** because the strategy is `:one_for_one`, a crash in one
  match does not affect the others.

### 2.4 `Chess.GameServer` — one match

- **File:** [lib/chess/game_server.ex](../lib/chess/game_server.ex)
- **Type:** `GenServer` with `restart: :transient`
  ([lib/chess/game_server.ex:10](../lib/chess/game_server.ex#L10))
- **Registered as:** `{:via, Registry, {Chess.GameRegistry, room_id}}`
  ([lib/chess/game_server.ex:49](../lib/chess/game_server.ex#L49))
- **State:** `%Chess.GameServer.State{}`
  ([lib/chess/game_server.ex:16-28](../lib/chess/game_server.ex#L16-L28))

  | Field          | Meaning                                                |
  |----------------|--------------------------------------------------------|
  | `room_id`      | Public id; same key the registry uses                  |
  | `mode`         | `:solo` or `:multiplayer`                              |
  | `players`      | `%{white: nickname, black: nickname}`                  |
  | `game_pid`     | Pid of the underlying binbo engine (see 2.5)           |
  | `side_to_move` | `:white` or `:black`                                   |
  | `status`       | `:in_progress \| {:checkmate, _} \| {:draw, _} \| {:winner, color, reason} \| :ended` |
  | `history`      | List of played moves                                   |
  | `started_at`   | Unix seconds                                           |

- **Responsibility:** own a single match end-to-end:
  - validate that the move is being requested by a player who exists in
    this match (`color_for/2`,
    [lib/chess/game_server.ex:154-158](../lib/chess/game_server.ex#L154-L158)),
  - validate it is that player's turn (`ensure_turn_for/2`,
    [lib/chess/game_server.ex:160-168](../lib/chess/game_server.ex#L160-L168)),
  - delegate legality and rules to `Chess.Game` (binbo),
  - keep the move history,
  - broadcast every state change so subscribed LiveViews re-render.
- **Public API:** `get_state/1`, `legal_moves_from/2`, `move/5`,
  `resign/2`, `stop/1`
  ([lib/chess/game_server.ex:36-47](../lib/chess/game_server.ex#L36-L47)).
- **Broadcasts:** publishes `{:game_state, public_state}` on
  `"game:" <> room_id` after every successful move or resignation
  ([lib/chess/game_server.ex:147-149](../lib/chess/game_server.ex#L147-L149)).
- **Cleanup:** `terminate/2` stops the underlying binbo pid
  ([lib/chess/game_server.ex:128-131](../lib/chess/game_server.ex#L128-L131)),
  so the engine cannot leak when the match dies.
- **Solo vs multiplayer:** in `:solo` mode `ensure_turn_for/2` always
  returns `:ok` (one human plays both sides), and resigning sets the
  status to `:ended`. In `:multiplayer` mode, resigning sets the status
  to `{:winner, opponent, :resign}`
  ([lib/chess/game_server.ex:102-125](../lib/chess/game_server.ex#L102-L125)).

### 2.5 `Chess.Game` — binbo engine wrapper

- **File:** [lib/chess/game.ex](../lib/chess/game.ex)
- **Type:** plain module (no GenServer of its own).
- **What it is:** a thin Elixir-flavoured wrapper around the
  [`binbo`](https://hex.pm/packages/binbo) chess engine. `binbo` itself
  exposes a server pid (`:binbo.new_server/0`,
  [lib/chess/game.ex:22-33](../lib/chess/game.ex#L22-L33)); this module
  hides that and converts Erlang-y returns into Elixir-y shapes.
- **Lifetime:** the binbo pid is created in `GameServer.init/1`
  ([lib/chess/game_server.ex:54-69](../lib/chess/game_server.ex#L54-L69))
  and stopped in `GameServer.terminate/2`. It lives and dies with its
  owning `GameServer` and is **not** part of the supervision tree.
- **Why it is not supervised:** it is owned data, conceptually like the
  socket of a `gen_tcp` connection — its lifetime is bound to its
  owner, and the owner already cleans it up. Exposing it as a
  supervised child would let two processes claim the same engine.

### 2.6 `Chess.Games` — façade

- **File:** [lib/chess/games.ex](../lib/chess/games.ex)
- **Type:** plain module. **Not a process.**
- **Responsibility:** the only API the web layer should call. Hides the
  registry/supervisor wiring behind functions like `start_game/1`,
  `lookup/1`, `move/5`, `resign/2`, `stop/1`.
- **Why it exists:** so LiveViews never call `DynamicSupervisor` or
  `Registry` directly. If the topology ever changes (e.g. moving to
  `:horde` for distributed games), only this module needs to change.

---

## 3. Lifecycle: creating a match

The diagrams below use `─►` for a synchronous call and `╌►` for an
asynchronous PubSub broadcast. Time flows top to bottom.

```
LobbyLive          Chess.Rooms       Chess.Games        GameSupervisor      GameRegistry        GameServer
   │                   │                   │                   │                  │                   │
   │ create(host)      │                   │                   │                  │                   │
   ├──────────────────►│                   │                   │                  │                   │
   │                   │ {:rooms_changed}  │                   │                  │                   │
   │ ◄╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤  (PubSub "lobby") │                   │                  │                   │
   │                   │                   │                   │                  │                   │
   │ join(room_id,     │                   │                   │                  │                   │
   │      guest)       │                   │                   │                  │                   │
   ├──────────────────►│                   │                   │                  │                   │
   │ ◄─────────────────┤ {:ok, room}       │                   │                  │                   │
   │                   │ {:room_joined}    │                   │                  │                   │
   │ ◄╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤  (PubSub "lobby") │                   │                  │                   │
   │                                                                                                  │
   │ start_game(%{room_id, mode, white, black})                                                       │
   ├─────────────────────────────────────►│                    │                  │                   │
   │                                      │ start_child(GameServer, opts)         │                   │
   │                                      ├───────────────────►│                  │                   │
   │                                      │                    │ start_link/init/1                    │
   │                                      │                    ├──────────────────────────────────────►│
   │                                      │                    │                  │ register(room_id) │
   │                                      │                    │                  │ ◄─────────────────┤
   │                                      │ ◄──────────────────┤ {:ok, pid}       │                   │
   │ ◄────────────────────────────────────┤ {:ok, pid}                                                 │
   │                                                                                                  │
   │ navigate to /games/:room_id                                                                      │
```

Notes:
- The host's browser is sitting in `LobbyLive` subscribed to the
  `"lobby"` topic; the `:room_joined` broadcast is what triggers its
  navigation to the game page.
- `Chess.Games.start_game/1` is the **only** caller that should ever
  add a child to `Chess.GameSupervisor`.

For solo mode the lobby is skipped entirely: the LiveView calls
`Chess.Games.start_game/1` directly with `mode: :solo` and a generated
`room_id`.

---

## 4. Lifecycle: making a move

```
GameLive (white)       Chess.Games        GameServer (room R)       Chess.Game / binbo       PubSub
   │                       │                       │                       │                    │
   │ select_square         │                       │                       │                    │
   │ → move(R, nick, e2, e4)                       │                       │                    │
   ├──────────────────────►│                       │                       │                    │
   │                       │ GenServer.call({:move, ...})                  │                    │
   │                       ├──────────────────────►│                       │                    │
   │                       │                       │ ensure_in_progress    │                    │
   │                       │                       │ color_for             │                    │
   │                       │                       │ ensure_turn_for       │                    │
   │                       │                       │ Game.move(pid, ...)   │                    │
   │                       │                       ├──────────────────────►│                    │
   │                       │                       │ ◄─────────────────────┤ {:ok, status}      │
   │                       │                       │ append history                             │
   │                       │                       │ flip side_to_move                          │
   │                       │                       │ broadcast {:game_state, ...}               │
   │                       │                       ├────────────────────────────────────────────►│
   │                       │ ◄─────────────────────┤ {:reply, {:ok, public_state}}              │
   │ ◄─────────────────────┤ {:ok, public_state}                                                 │
   │                                                                                            │
   │ ◄╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┤
GameLive (black)                                       (also subscribed to "game:R", re-renders)
```

Two relevant observations:
- The mover gets the new state both as the **call reply** and as a
  **broadcast**. The broadcast is the authoritative source so every
  client (mover and opponent) receives the same payload through the
  same code path.
- Validation happens entirely in the `GameServer`. The LiveView is
  trusted only to *attempt* a move; it cannot bypass turn order even if
  it wanted to.

---

## 5. Lifecycle: ending a match

A match can end in three ways:

1. **Checkmate / draw** — produced by binbo as part of a normal `move`
   call. The status is stored in `state.status`; the `GameServer`
   broadcasts and stays alive so clients can still call `get_state/1`.
   It will be terminated by `Chess.Games.stop/1` when no longer needed.
2. **Resignation** —
   [lib/chess/game_server.ex:102-125](../lib/chess/game_server.ex#L102-L125).
   In `:solo`, status becomes `:ended`. In `:multiplayer`, the
   underlying binbo is told who won (`Game.set_winner/3`,
   [lib/chess/game.ex:142-144](../lib/chess/game.ex#L142-L144)) and
   status becomes `{:winner, opponent, :resign}`.
3. **Explicit stop** — `Chess.Games.stop/1` calls
   `DynamicSupervisor.terminate_child/2`. The `GameServer` exits, and
   `terminate/2` stops the binbo pid as it goes
   ([lib/chess/game_server.ex:128-131](../lib/chess/game_server.ex#L128-L131)).

In none of these cases does the `GameServer` come back. See restart
semantics below.

---

## 6. Restart semantics

| Process              | Strategy             | What happens on crash                                                                                |
|----------------------|----------------------|------------------------------------------------------------------------------------------------------|
| `Chess.Supervisor`   | `:one_for_one`       | One subsystem (lobby, registry, game supervisor) dying does not take down the others.                 |
| `Chess.Rooms`        | default (`:permanent`) | Restarted by the root supervisor. **The lobby is wiped** — state is in-memory only.                 |
| `Chess.GameRegistry` | default (`:permanent`) | Restarted. All registered names are lost; running `GameServer`s would need to be re-registered.     |
| `Chess.GameSupervisor` | default (`:permanent`) | Restarted empty. All running matches are also restarted under it (per OTP rules) — see next row.  |
| `Chess.GameServer`   | `:transient`         | Normal exit (`:normal`/`:shutdown`) → **not** restarted. Abnormal crash → restarted, but `init/1` builds a fresh state, so **history is lost**. |

Two consequences worth remembering:

- **A match that finishes naturally is gone.** That is the whole point
  of `restart: :transient` here — once a game is over, we don't want
  the dynamic supervisor to keep respawning it.
- **A crashed match restarts to move 1.** The `GameServer` does not
  persist the FEN anywhere; recovery is best-effort. If durability is
  ever needed, persistence belongs in `init/1` (load) and after each
  successful `move` (save).

---

## 7. Inspecting the tree at runtime

```elixir
iex -S mix phx.server

# Visual tree of every supervisor in the BEAM
:observer.start()

# How many matches are running, and their pids
DynamicSupervisor.which_children(Chess.GameSupervisor)
DynamicSupervisor.count_children(Chess.GameSupervisor)

# Find the GameServer for a specific room
Registry.lookup(Chess.GameRegistry, "ABC123")
# => [{#PID<0.512.0>, nil}]

# Read a match's public state (FEN, history, status, players)
Chess.Games.get_state("ABC123")

# Force-stop a match
Chess.Games.stop("ABC123")
```

If `Registry.lookup/2` returns `[]`, either the `room_id` is wrong or
the match has already ended (`:transient` exit removed it from the
supervisor and the registry).
