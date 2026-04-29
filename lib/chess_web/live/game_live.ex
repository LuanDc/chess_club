defmodule ChessWeb.GameLive do
  use ChessWeb, :live_view

  alias Chess.Games

  @impl true
  def mount(params, _session, socket) do
    case socket.assigns.live_action do
      :solo -> mount_solo(socket)
      :show -> mount_multiplayer(params, socket)
    end
  end

  defp mount_solo(socket) do
    nick = socket.assigns.nickname
    room_id = "solo-#{:erlang.unique_integer([:positive, :monotonic])}-#{nick}"

    case Games.start_game(%{room_id: room_id, mode: :solo, white: nick, black: nick}) do
      {:ok, _pid} ->
        {:ok, init_assigns(socket, room_id, :solo)}

      {:error, _} ->
        {:ok, init_assigns(socket, room_id, :solo)}
    end
  end

  defp mount_multiplayer(%{"room_id" => room_id}, socket) do
    case Games.lookup(room_id) do
      {:ok, _pid} ->
        {:ok, init_assigns(socket, room_id, :multiplayer)}

      {:error, :not_found} ->
        {:ok, push_navigate(socket, to: ~p"/lobby")}
    end
  end

  defp init_assigns(socket, room_id, mode) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Chess.PubSub, "game:" <> room_id)
    end

    state = Games.get_state(room_id)
    nick = socket.assigns.nickname
    my_color = my_color(state, nick, mode)

    socket
    |> assign(
      room_id: room_id,
      mode: mode,
      state: state,
      pieces: pieces_from_state(state),
      my_color: my_color,
      orientation: orientation(my_color),
      selected: nil,
      legal_targets: []
    )
  end

  defp my_color(_state, _nick, :solo), do: :solo
  defp my_color(%{players: %{white: nick}}, nick, _), do: :white
  defp my_color(%{players: %{black: nick}}, nick, _), do: :black
  defp my_color(_, _, _), do: :spectator

  defp orientation(:black), do: :black
  defp orientation(_), do: :white

  defp pieces_from_state(%{fen: fen}), do: pieces_from_fen(fen)

  defp pieces_from_fen(fen) do
    [pos | _] = String.split(fen, " ")

    pos
    |> String.split("/")
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {row, idx}, acc ->
      rank = 8 - idx

      row
      |> String.graphemes()
      |> Enum.reduce({?a, acc}, fn ch, {file, acc2} ->
        case Integer.parse(ch) do
          {n, ""} ->
            {file + n, acc2}

          :error ->
            piece = decode_piece(ch)
            sq = <<file>> <> Integer.to_string(rank)
            {file + 1, Map.put(acc2, sq, piece)}
        end
      end)
      |> elem(1)
    end)
  end

  defp decode_piece(c) do
    color = if c == String.upcase(c), do: :white, else: :black

    piece =
      case String.downcase(c) do
        "p" -> :pawn
        "n" -> :knight
        "b" -> :bishop
        "r" -> :rook
        "q" -> :queen
        "k" -> :king
      end

    {color, piece}
  end

  ## Events ──────────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_square", %{"square" => sq}, socket) do
    %{state: state, selected: selected, my_color: my_color, mode: mode} = socket.assigns

    cond do
      game_over?(state) ->
        {:noreply, socket}

      not can_act?(state, my_color, mode) ->
        {:noreply, socket}

      selected == sq ->
        {:noreply, assign(socket, selected: nil, legal_targets: [])}

      selected != nil and sq in socket.assigns.legal_targets ->
        case Games.move(socket.assigns.room_id, socket.assigns.nickname, selected, sq) do
          {:ok, new_state} ->
            {:noreply,
             socket
             |> assign(state: new_state, pieces: pieces_from_state(new_state))
             |> assign(selected: nil, legal_targets: [])}

          {:error, _} ->
            {:noreply, assign(socket, selected: nil, legal_targets: [])}
        end

      true ->
        # try to (re)select a piece on the square
        select_piece(socket, sq)
    end
  end

  def handle_event("resign", _params, socket) do
    case Games.resign(socket.assigns.room_id, socket.assigns.nickname) do
      {:ok, new_state} ->
        {:noreply,
         socket
         |> assign(state: new_state, pieces: pieces_from_state(new_state))
         |> assign(selected: nil, legal_targets: [])}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("back_to_lobby", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/lobby")}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp select_piece(socket, sq) do
    %{pieces: pieces, my_color: my_color, mode: mode, state: state} = socket.assigns

    case Map.get(pieces, sq) do
      {color, _piece} when mode == :solo and color == state.side_to_move ->
        targets = legal_targets_for(socket.assigns.room_id, sq)
        {:noreply, assign(socket, selected: sq, legal_targets: targets)}

      {color, _piece} when color == my_color and color == state.side_to_move ->
        targets = legal_targets_for(socket.assigns.room_id, sq)
        {:noreply, assign(socket, selected: sq, legal_targets: targets)}

      _ ->
        {:noreply, assign(socket, selected: nil, legal_targets: [])}
    end
  end

  defp legal_targets_for(room_id, sq) do
    case Games.lookup(room_id) do
      {:ok, _pid} ->
        # We need the underlying Game pid; fetch through state for now
        # by using Chess.Game directly via a small detour through Games.
        Chess.Games.legal_moves_from(room_id, sq)

      _ ->
        []
    end
  end

  defp game_over?(%{status: :in_progress}), do: false
  defp game_over?(_), do: true

  defp can_act?(_state, :solo, :solo), do: true
  defp can_act?(%{side_to_move: color}, color, _mode), do: true
  defp can_act?(_, _, _), do: false

  ## PubSub ──────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:game_state, state}, socket) do
    {:noreply,
     assign(socket,
       state: state,
       pieces: pieces_from_state(state),
       selected: nil,
       legal_targets: []
     )}
  end

  ## Render ──────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <.navbar>
        <:right>
          <.solo_badge :if={@mode == :solo} />
          <.link
            patch={~p"/lobby"}
            class="inline-flex items-center justify-center px-3.5 py-1.5 text-[13px] rounded-md border border-border2 text-text hover:bg-surface2"
          >
            ← Lobby
          </.link>
        </:right>
      </.navbar>

      <div class="flex-1 flex items-start justify-center gap-12 p-12 flex-row">
        <div class="flex flex-col flex-1 animate-fade-up">
          <.player_bar
            position="top"
            name={top_name(@state, @my_color, @mode)}
            color_label={top_color_label(@my_color, @mode)}
            active?={top_active?(@state, @my_color, @mode)}
          />

          <.board
            pieces={@pieces}
            orientation={@orientation}
            selected={@selected}
            legal_targets={@legal_targets}
            disabled={@state.status != :in_progress}
          />

          <.player_bar
            position="bottom"
            name={bottom_name(@state, @my_color, @mode)}
            color_label={bottom_color_label(@my_color, @mode)}
            active?={bottom_active?(@state, @my_color, @mode)}
            you?={@mode != :solo}
          />
        </div>

        <div class="w-64 flex flex-col gap-3.5 pt-0 animate-fade-up">
          <%= if game_over?(@state) do %>
            <.game_over_card message={game_over_message(@state, @nickname, @my_color, @mode)}>
              <.btn variant="primary" phx-click="back_to_lobby" class="w-full">
                Voltar ao Lobby
              </.btn>
            </.game_over_card>
          <% else %>
            <.card>
              <.card_label>Status da Partida</.card_label>
              <div class="font-display text-[20px] font-semibold text-text leading-tight">
                {status_text(@state, @my_color, @mode)}
              </div>
              <div :if={@state.status == :in_progress} class="text-[13px] text-muted mt-1.5 italic">
                {status_sub(@state, @my_color, @mode)}
              </div>
              <.btn variant="danger" phx-click="resign" class="w-full mt-4">
                {if @mode == :solo, do: "Encerrar Partida", else: "Desistir"}
              </.btn>
            </.card>
          <% end %>

          <.card>
            <.card_label>Movimentos · {length(@state.history)}</.card_label>
            <.move_history moves={@state.history} />
          </.card>
        </div>
      </div>
    </div>
    """
  end

  ## Render helpers ──────────────────────────────────────────────────────

  defp top_name(_state, :solo, _), do: "Pretas"
  defp top_name(state, :white, _), do: state.players.black
  defp top_name(state, :black, _), do: state.players.white
  defp top_name(state, _, _), do: state.players.black

  defp bottom_name(_state, :solo, _), do: "Brancas"
  defp bottom_name(state, :white, _), do: state.players.white
  defp bottom_name(state, :black, _), do: state.players.black
  defp bottom_name(state, _, _), do: state.players.white

  defp top_color_label(:solo, _), do: nil
  defp top_color_label(:white, _), do: "Pretas"
  defp top_color_label(:black, _), do: "Brancas"
  defp top_color_label(_, _), do: nil

  defp bottom_color_label(:solo, _), do: nil
  defp bottom_color_label(:white, _), do: "Brancas"
  defp bottom_color_label(:black, _), do: "Pretas"
  defp bottom_color_label(_, _), do: nil

  defp top_active?(_state, :solo, _), do: false

  defp top_active?(state, :white, _),
    do: state.status == :in_progress and state.side_to_move == :black

  defp top_active?(state, :black, _),
    do: state.status == :in_progress and state.side_to_move == :white

  defp top_active?(_, _, _), do: false

  defp bottom_active?(_state, :solo, _), do: false

  defp bottom_active?(state, :white, _),
    do: state.status == :in_progress and state.side_to_move == :white

  defp bottom_active?(state, :black, _),
    do: state.status == :in_progress and state.side_to_move == :black

  defp bottom_active?(_, _, _), do: false

  defp status_text(%{status: :in_progress, side_to_move: :white}, _, _), do: "Vez das brancas"
  defp status_text(%{status: :in_progress, side_to_move: :black}, _, _), do: "Vez das pretas"
  defp status_text(%{status: {:checkmate, _}}, _, _), do: "Xeque-mate!"
  defp status_text(%{status: {:draw, _}}, _, _), do: "Empate"
  defp status_text(%{status: {:winner, _, _}}, _, _), do: "Fim de jogo"
  defp status_text(%{status: :ended}, _, _), do: "Partida encerrada"
  defp status_text(_, _, _), do: "…"

  defp status_sub(_state, :solo, :solo), do: "Mova as peças livremente"

  defp status_sub(state, my_color, _) do
    if state.side_to_move == my_color, do: "Sua vez de mover", else: "Aguardando oponente"
  end

  defp game_over_message(%{status: :ended}, _nick, _my_color, :solo),
    do: "Você encerrou a partida."

  defp game_over_message(
         %{status: {:winner, winner_color, :resign}, players: players},
         nick,
         _,
         _
       ) do
    winner = Map.get(players, winner_color)
    loser = Map.get(players, other_color(winner_color))

    cond do
      winner == nick -> "#{loser} desistiu. Você venceu! 🎉"
      loser == nick -> "Você desistiu da partida."
      true -> "#{loser} desistiu. #{winner} venceu."
    end
  end

  defp game_over_message(%{status: {:checkmate, who_wins}, players: players}, nick, _, _) do
    winner_color = if who_wins == :white_wins, do: :white, else: :black
    winner = Map.get(players, winner_color)

    if winner == nick do
      "Xeque-mate! Você venceu! 🎉"
    else
      "Xeque-mate! #{winner} venceu."
    end
  end

  defp game_over_message(%{status: {:draw, _}}, _nick, _my, _mode), do: "Empate! 🤝"
  defp game_over_message(_, _, _, _), do: "Partida encerrada."

  defp other_color(:white), do: :black
  defp other_color(:black), do: :white
end
