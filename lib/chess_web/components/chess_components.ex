defmodule ChessWeb.ChessComponents do
  @moduledoc """
  Domain-specific reusable components for the Chess Club app:
  navbar, room_card, empty_state, tip_bar, player_bar, board, etc.
  """
  use Phoenix.Component

  import ChessWeb.UiComponents, only: [avatar: 1, btn: 1]

  ## Navbar ──────────────────────────────────────────────────────────────

  slot :right

  def navbar(assigns) do
    ~H"""
    <nav class="bg-surface border-b border-border px-8 py-3.5 flex items-center justify-between sticky top-0 z-50">
      <a
        href="/"
        class="flex items-center gap-2 select-none font-display text-[22px] font-bold text-text tracking-[.03em]"
      >
        <span class="text-accent text-[24px]">♚</span> Chess Club
      </a>
      <div class="flex items-center gap-3">
        {render_slot(@right)}
      </div>
    </nav>
    """
  end

  ## Empty state ─────────────────────────────────────────────────────────

  attr :glyph, :string, default: "⌧"
  attr :title, :string, required: true
  attr :description, :string, default: nil

  def empty_state(assigns) do
    ~H"""
    <div class="text-center px-5 py-16">
      <div class="font-display text-[56px] text-faint leading-none mb-4">{@glyph}</div>
      <h3 class="font-display text-[22px] font-semibold mb-2 text-text">{@title}</h3>
      <p :if={@description} class="text-muted text-sm leading-[1.65]">
        {@description}
      </p>
    </div>
    """
  end

  ## Tip bar ─────────────────────────────────────────────────────────────

  slot :inner_block, required: true

  def tip_bar(assigns) do
    ~H"""
    <div class="mt-9 px-5 py-4 bg-surface2 border border-border rounded-lg text-[13px] text-muted leading-[1.6] text-center">
      {render_slot(@inner_block)}
    </div>
    """
  end

  ## Section pulse (animated dot) ───────────────────────────────────────

  def pulse(assigns) do
    ~H"""
    <span class="inline-block w-1.5 h-1.5 rounded-full bg-accent animate-blink"></span>
    """
  end

  ## Room card ───────────────────────────────────────────────────────────

  attr :room, :map, required: true
  attr :mine?, :boolean, default: false

  def room_card(%{mine?: true} = assigns) do
    ~H"""
    <div class="bg-accent/[.08] border border-accent/25 rounded-[9px] px-[22px] py-[18px] flex items-center justify-between">
      <div>
        <div class="font-display font-semibold text-[17px] mb-0.5 flex items-center gap-2">
          <.avatar name={@room.host} size="sm" /> Sua sala
        </div>
        <div class="text-xs text-muted flex items-center gap-1.5">
          <.pulse /> Aguardando oponente…
        </div>
      </div>
      <span class="text-[11px] font-mono text-faint bg-surface2 px-2.5 py-1 rounded border border-border">
        #{@room.id}
      </span>
    </div>
    """
  end

  def room_card(%{mine?: false} = assigns) do
    ~H"""
    <div class="bg-surface border border-border rounded-[9px] px-[22px] py-[18px] flex items-center justify-between transition hover:border-accent/25 hover:shadow-[0_2px_12px_rgba(61,107,79,.07)]">
      <div>
        <div class="font-display font-semibold text-[17px] mb-0.5 flex items-center gap-2">
          <.avatar name={@room.host} size="sm" />
          {@room.host}
        </div>
        <div class="text-xs text-muted flex items-center gap-1.5">
          <.pulse /> Procurando oponente
        </div>
      </div>
      <.btn variant="outline" phx-click="join_room" phx-value-room-id={@room.id}>
        Entrar →
      </.btn>
    </div>
    """
  end

  ## Player bar ──────────────────────────────────────────────────────────

  attr :name, :string, required: true
  attr :color_label, :string, default: nil
  attr :active?, :boolean, default: false
  attr :you?, :boolean, default: false
  attr :position, :string, default: "top", values: ~w(top bottom)

  def player_bar(assigns) do
    ~H"""
    <div class={[
      "bg-surface border border-border rounded-lg px-3.5 py-2.5 flex items-center gap-2.5 transition",
      @position == "top" && "mb-2",
      @position == "bottom" && "mt-2",
      @active? && "!border-accent !bg-accent/[.08]"
    ]}>
      <.avatar name={@name} size="sm" />
      <span class="font-display font-semibold text-[17px] flex-1">
        {@name}
        <span :if={@you?} class="font-normal text-muted text-[13px] ml-1.5 italic">(você)</span>
      </span>
      <span
        :if={@color_label}
        class="text-[11px] text-muted bg-surface2 px-2 py-0.5 rounded font-serif"
      >
        {@color_label}
      </span>
    </div>
    """
  end

  ## Board ───────────────────────────────────────────────────────────────

  @piece_glyphs %{
    {:white, :king} => "♔",
    {:white, :queen} => "♕",
    {:white, :rook} => "♖",
    {:white, :bishop} => "♗",
    {:white, :knight} => "♘",
    {:white, :pawn} => "♙",
    {:black, :king} => "♚",
    {:black, :queen} => "♛",
    {:black, :rook} => "♜",
    {:black, :bishop} => "♝",
    {:black, :knight} => "♞",
    {:black, :pawn} => "♟"
  }

  attr :pieces, :map, required: true, doc: "map of square -> {color, piece}"
  attr :orientation, :atom, default: :white, values: [:white, :black]
  attr :selected, :string, default: nil
  attr :legal_targets, :list, default: []
  attr :disabled, :boolean, default: false

  def board(assigns) do
    assigns =
      assigns
      |> assign_new(:ranks, fn -> rank_order(assigns.orientation) end)
      |> assign_new(:files, fn -> file_order(assigns.orientation) end)

    ~H"""
    <div class="grid grid-cols-8 grid-rows-8 select-none aspect-square w-full max-w-[480px] border border-border2 shadow-[0_4px_24px_rgba(44,40,32,.08)] rounded-sm overflow-hidden">
      <%= for rank <- @ranks, file <- @files, sq = "#{<<file>>}#{rank}" do %>
        <button
          type="button"
          data-square={sq}
          data-selected={if @selected == sq, do: "true"}
          data-target={if sq in @legal_targets, do: "true"}
          phx-click="select_square"
          phx-value-square={sq}
          disabled={@disabled}
          class={[
            "relative flex items-center justify-center text-[40px] leading-none transition",
            square_color(file, rank),
            @selected == sq && "ring-4 ring-inset ring-accent/70 z-10",
            sq in @legal_targets &&
              "after:absolute after:inset-0 after:m-auto after:w-3 after:h-3 after:rounded-full after:bg-accent/40"
          ]}
        >
          <span class={piece_color_class(@pieces[sq])}>
            {piece_glyph(@pieces[sq])}
          </span>
        </button>
      <% end %>
    </div>
    """
  end

  defp rank_order(:white), do: 8..1//-1 |> Enum.to_list()
  defp rank_order(:black), do: 1..8 |> Enum.to_list()

  defp file_order(:white), do: ?a..?h |> Enum.to_list()
  defp file_order(:black), do: ?h..?a//-1 |> Enum.to_list()

  defp square_color(file, rank) do
    if rem(file + rank, 2) == 0 do
      "bg-board-dark"
    else
      "bg-board-light"
    end
  end

  defp piece_glyph(nil), do: ""
  defp piece_glyph({_color, _piece} = key), do: Map.get(@piece_glyphs, key, "")

  defp piece_color_class(nil), do: ""
  defp piece_color_class({:white, _}), do: "text-white drop-shadow-[0_1px_1px_rgba(0,0,0,.45)]"
  defp piece_color_class({:black, _}), do: "text-black"

  ## Move history ────────────────────────────────────────────────────────

  attr :moves, :list, required: true, doc: "list of %{from, to, color}"

  def move_history(assigns) do
    pairs =
      assigns.moves
      |> Enum.chunk_every(2)
      |> Enum.with_index(1)
      |> Enum.map(fn {chunk, n} ->
        {n, Enum.at(chunk, 0), Enum.at(chunk, 1)}
      end)

    last_n = length(pairs)
    last_color = if rem(length(assigns.moves), 2) == 1, do: :white, else: :black

    assigns =
      assign(assigns,
        pairs: pairs,
        total: length(assigns.moves),
        last_n: last_n,
        last_color: last_color
      )

    ~H"""
    <div :if={@total == 0} class="text-faint text-[13px] italic">Nenhum ainda…</div>

    <div :if={@total > 0} class="max-h-[300px] overflow-y-auto">
      <div
        :for={{n, w, b} <- @pairs}
        class="grid grid-cols-[26px_1fr_1fr] gap-0.5 py-1 border-b border-border last:border-b-0 text-[13px] font-serif"
      >
        <span class="text-faint">{n}.</span>
        <span
          data-latest={if w && n == @last_n && @last_color == :white, do: "true"}
          class={[
            "px-1 py-px rounded",
            w && n == @last_n && @last_color == :white && "bg-accent/[.08] text-accent font-semibold"
          ]}
        >{if w, do: format_move(w), else: ""}</span>
        <span
          data-latest={if b && n == @last_n && @last_color == :black, do: "true"}
          class={[
            "px-1 py-px rounded",
            b && n == @last_n && @last_color == :black && "bg-accent/[.08] text-accent font-semibold"
          ]}
        >{if b, do: format_move(b), else: ""}</span>
      </div>
    </div>
    """
  end

  defp format_move(%{from: from, to: to}), do: "#{from}-#{to}"

  ## Game over card ──────────────────────────────────────────────────────

  attr :title, :string, default: "Fim de Jogo"
  attr :message, :string, required: true
  slot :inner_block

  def game_over_card(assigns) do
    ~H"""
    <div class="bg-surface border border-accent/25 rounded-[10px] px-5 py-[22px] text-center shadow-[0_2px_14px_rgba(61,107,79,.1)]">
      <h2 class="font-display text-2xl font-bold text-accent mb-1.5">{@title}</h2>
      <p class="text-muted text-sm mb-4 leading-snug">{@message}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  ## Waiting overlay ─────────────────────────────────────────────────────

  attr :title, :string, default: "Aguardando oponente…"
  attr :description, :string, default: "Compartilhe o link da sala com um amigo."

  def waiting_overlay(assigns) do
    ~H"""
    <div class="absolute inset-0 bg-bg/90 flex flex-col items-center justify-center rounded-sm z-10 backdrop-blur-sm">
      <span class="text-5xl text-accent/60 mb-3.5 animate-bob">⌛</span>
      <h3 class="font-display text-[22px] font-semibold text-text mb-1">{@title}</h3>
      <p class="text-muted text-[13px]">{@description}</p>
    </div>
    """
  end

  ## Solo badge ──────────────────────────────────────────────────────────

  def solo_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5 px-2.5 py-0.5 bg-warm/10 border border-warm/20 rounded-full text-[11px] text-warm tracking-[.04em]">
      ⌧ Modo solo
    </span>
    """
  end
end
