defmodule Chess.Rooms do
  @moduledoc """
  In-memory store of open lobby rooms. A "room" is created by a host
  and waits for a guest. Joining or cancelling removes it. Rooms older
  than `@ttl_seconds` are pruned lazily on `list/1`.

  Every state-changing operation broadcasts `{:rooms_changed, rooms}`
  on the configured PubSub topic so LiveViews can update without
  polling.
  """
  use GenServer

  alias __MODULE__.Room

  @default_name __MODULE__
  @default_pubsub Chess.PubSub
  @default_topic "lobby"
  @ttl_seconds 10 * 60

  defmodule Room do
    @enforce_keys [:id, :host, :inserted_at]
    defstruct [:id, :host, :guest, :inserted_at]

    @type t :: %__MODULE__{
            id: String.t(),
            host: String.t(),
            guest: String.t() | nil,
            inserted_at: integer()
          }
  end

  ## Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def create(server \\ @default_name, host) when is_binary(host),
    do: GenServer.call(server, {:create, host})

  def list(server \\ @default_name),
    do: GenServer.call(server, :list)

  def find(server \\ @default_name, room_id),
    do: GenServer.call(server, {:find, room_id})

  def cancel(server \\ @default_name, room_id, host),
    do: GenServer.call(server, {:cancel, room_id, host})

  def join(server \\ @default_name, room_id, guest),
    do: GenServer.call(server, {:join, room_id, guest})

  @doc "Clears all rooms. Test helper."
  def clear(server \\ @default_name),
    do: GenServer.call(server, :clear)

  @doc false
  def __force_age__(server, room_id, delta_seconds),
    do: GenServer.call(server, {:force_age, room_id, delta_seconds})

  ## Server callbacks

  @impl true
  def init(opts) do
    state = %{
      rooms: [],
      pubsub: Keyword.get(opts, :pubsub, @default_pubsub),
      topic: Keyword.get(opts, :topic, @default_topic)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:create, host}, _from, state) do
    rooms_without_host = Enum.reject(state.rooms, &(&1.host == host))

    room = %Room{
      id: generate_id(),
      host: host,
      guest: nil,
      inserted_at: now()
    }

    new_state = %{state | rooms: rooms_without_host ++ [room]}
    {state2, fresh} = prune(new_state)
    broadcast(state2, fresh)
    {:reply, {:ok, room}, state2}
  end

  def handle_call(:list, _from, state) do
    {state2, fresh} = prune(state)
    {:reply, fresh, state2}
  end

  def handle_call({:find, id}, _from, state) do
    {state2, fresh} = prune(state)

    case Enum.find(fresh, &(&1.id == id)) do
      nil -> {:reply, :error, state2}
      room -> {:reply, {:ok, room}, state2}
    end
  end

  def handle_call({:cancel, id, host}, _from, state) do
    {state2, fresh} = prune(state)

    case Enum.find(fresh, &(&1.id == id)) do
      nil ->
        {:reply, {:error, :not_found}, state2}

      %Room{host: ^host} ->
        new_rooms = Enum.reject(fresh, &(&1.id == id))
        state3 = %{state2 | rooms: new_rooms}
        broadcast(state3, new_rooms)
        {:reply, :ok, state3}

      _ ->
        {:reply, {:error, :forbidden}, state2}
    end
  end

  def handle_call({:join, id, guest}, _from, state) do
    {state2, fresh} = prune(state)

    case Enum.find(fresh, &(&1.id == id)) do
      nil ->
        {:reply, {:error, :not_found}, state2}

      %Room{host: ^guest} ->
        {:reply, {:error, :cannot_join_own_room}, state2}

      %Room{} = room ->
        joined = %Room{room | guest: guest}
        new_rooms = Enum.reject(fresh, &(&1.id == id))
        state3 = %{state2 | rooms: new_rooms}
        broadcast(state3, new_rooms)
        broadcast_join(state3, joined)
        {:reply, {:ok, joined}, state3}
    end
  end

  def handle_call(:clear, _from, state) do
    new_state = %{state | rooms: []}
    broadcast(new_state, [])
    {:reply, :ok, new_state}
  end

  def handle_call({:force_age, room_id, delta_seconds}, _from, state) do
    rooms =
      Enum.map(state.rooms, fn
        %Room{id: ^room_id} = r -> %Room{r | inserted_at: r.inserted_at + delta_seconds}
        r -> r
      end)

    {:reply, :ok, %{state | rooms: rooms}}
  end

  ## Helpers

  defp prune(state) do
    cutoff = now() - @ttl_seconds
    {fresh, expired} = Enum.split_with(state.rooms, &(&1.inserted_at >= cutoff))

    if expired == [] do
      {state, fresh}
    else
      new_state = %{state | rooms: fresh}
      broadcast(new_state, fresh)
      {new_state, fresh}
    end
  end

  defp broadcast(%{pubsub: pubsub, topic: topic}, rooms) do
    Phoenix.PubSub.broadcast(pubsub, topic, {:rooms_changed, rooms})
  end

  defp broadcast_join(%{pubsub: pubsub, topic: topic}, %Room{} = room) do
    Phoenix.PubSub.broadcast(pubsub, topic, {:room_joined, room})
  end

  defp generate_id do
    bytes = :crypto.strong_rand_bytes(4)
    bytes |> Base.encode16() |> binary_part(0, 6)
  end

  defp now, do: System.system_time(:second)
end
