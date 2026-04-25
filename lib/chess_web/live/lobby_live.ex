defmodule ChessWeb.LobbyLive do
  use ChessWeb, :live_view

  alias Chess.{Games, Rooms}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Chess.PubSub, "lobby")
    end

    {:ok, assign_rooms(socket)}
  end

  @impl true
  def handle_event("create_room", _params, socket) do
    {:ok, _room} = Rooms.create(socket.assigns.nickname)
    {:noreply, assign_rooms(socket)}
  end

  def handle_event("cancel_room", _params, socket) do
    %{nickname: nick, my_room: my_room} = socket.assigns

    if my_room, do: Rooms.cancel(my_room.id, nick)

    {:noreply, assign_rooms(socket)}
  end

  def handle_event("join_room", %{"room-id" => room_id}, socket) do
    nick = socket.assigns.nickname

    with {:ok, room} <- Rooms.find(room_id),
         {:ok, _pid} <- ensure_game(room, nick),
         {:ok, _joined} <- Rooms.join(room_id, nick) do
      {:noreply, push_navigate(socket, to: ~p"/games/#{room_id}")}
    else
      _ -> {:noreply, assign_rooms(socket)}
    end
  end

  def handle_event("play_solo", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/games/solo")}
  end

  @impl true
  def handle_info({:rooms_changed, _rooms}, socket) do
    {:noreply, assign_rooms(socket)}
  end

  def handle_info({:room_joined, room}, socket) do
    if room.host == socket.assigns.nickname do
      {:noreply, push_navigate(socket, to: ~p"/games/#{room.id}")}
    else
      {:noreply, socket}
    end
  end

  defp ensure_game(room, guest) do
    case Games.start_game(%{
           room_id: room.id,
           mode: :multiplayer,
           white: room.host,
           black: guest
         }) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      err -> err
    end
  end

  defp assign_rooms(socket) do
    rooms = Rooms.list()
    nickname = socket.assigns.nickname
    {mine, others} = Enum.split_with(rooms, &(&1.host == nickname))

    assign(socket, my_room: List.first(mine), other_rooms: others)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <.navbar>
        <:right>
          <div class="flex items-center gap-2 text-[14px] text-muted">
            <.avatar name={@nickname} size="sm" />
            <span>{@nickname}</span>
          </div>
          <.link
            href={~p"/session"}
            method="delete"
            class="inline-flex items-center justify-center px-3.5 py-1.5 text-[13px] rounded-md border border-border2 text-text hover:bg-surface2"
          >
            Sair
          </.link>
        </:right>
      </.navbar>

      <div class="flex-1 max-w-[800px] mx-auto px-6 py-11 w-full animate-fade-up">
        <div class="mb-9">
          <h2 class="font-display text-[30px] font-semibold text-text mb-1.5">
            Bem-vindo, {@nickname}.
          </h2>
          <p class="text-muted text-sm leading-[1.6]">
            Crie uma sala e aguarde um oponente, ou entre na sala de alguém.
          </p>
        </div>

        <div class="flex gap-2.5 flex-wrap mb-9">
          <%= if @my_room do %>
            <.btn variant="ghost" phx-click="cancel_room">Cancelar Sala</.btn>
          <% else %>
            <.btn variant="primary" phx-click="create_room">+ Criar Sala</.btn>
          <% end %>
          <.btn variant="solo" phx-click="play_solo">⌧ Jogar Sozinho</.btn>
        </div>

        <.section_label>
          Salas abertas{if length(@other_rooms) > 0, do: " · #{length(@other_rooms)}", else: ""}
        </.section_label>

        <div class="flex flex-col gap-2">
          <.room_card :if={@my_room} room={@my_room} mine?={true} />

          <.empty_state
            :if={!@my_room and @other_rooms == []}
            glyph="⌧"
            title="Nenhuma sala disponível"
            description="Crie uma sala e aguarde um oponente."
          />

          <.room_card :for={room <- @other_rooms} room={room} mine?={false} />
        </div>

        <.tip_bar>
          💡 Para jogar com um amigo: <strong>compartilhe esta página</strong>
          ou abra em duas abas com nicknames diferentes.
        </.tip_bar>
      </div>
    </div>
    """
  end
end
