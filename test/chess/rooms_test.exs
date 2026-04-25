defmodule Chess.RoomsTest do
  use ExUnit.Case, async: false

  alias Chess.Rooms

  setup do
    # Each test gets a fresh GenServer instance under a unique name
    name = :"rooms_#{System.unique_integer([:positive])}"
    pubsub = Chess.PubSub
    topic = "lobby_test_#{System.unique_integer([:positive])}"

    {:ok, _pid} = start_supervised({Rooms, name: name, pubsub: pubsub, topic: topic})

    Phoenix.PubSub.subscribe(pubsub, topic)

    %{server: name, topic: topic}
  end

  describe "create/2" do
    test "creates a new room owned by host", %{server: server} do
      assert {:ok, %Rooms.Room{} = room} = Rooms.create(server, "Alice")
      assert room.host == "Alice"
      assert is_binary(room.id) and byte_size(room.id) > 0
      assert [%Rooms.Room{host: "Alice"}] = Rooms.list(server)
    end

    test "broadcasts :rooms_changed to subscribers", %{server: server} do
      {:ok, _room} = Rooms.create(server, "Alice")
      assert_receive {:rooms_changed, [%Rooms.Room{host: "Alice"}]}
    end

    test "host can have only one open room at a time", %{server: server} do
      {:ok, _r1} = Rooms.create(server, "Alice")
      {:ok, _r2} = Rooms.create(server, "Alice")
      assert [_only_one] = Rooms.list(server)
    end
  end

  describe "list/1" do
    test "returns rooms in insertion order", %{server: server} do
      {:ok, _} = Rooms.create(server, "Alice")
      {:ok, _} = Rooms.create(server, "Bob")
      assert [%{host: "Alice"}, %{host: "Bob"}] = Rooms.list(server)
    end

    test "prunes rooms older than 10 minutes", %{server: server} do
      {:ok, room} = Rooms.create(server, "Stale")
      # Force the room's inserted_at to be 11 minutes ago
      :ok = Rooms.__force_age__(server, room.id, -11 * 60)

      assert [] = Rooms.list(server)
    end
  end

  describe "find/2" do
    test "returns room by id", %{server: server} do
      {:ok, room} = Rooms.create(server, "Alice")
      assert {:ok, ^room} = Rooms.find(server, room.id)
    end

    test "returns :error when not found", %{server: server} do
      assert :error = Rooms.find(server, "MISSING")
    end
  end

  describe "cancel/3" do
    test "removes the room when host matches", %{server: server} do
      {:ok, room} = Rooms.create(server, "Alice")
      assert :ok = Rooms.cancel(server, room.id, "Alice")
      assert [] = Rooms.list(server)
    end

    test "rejects cancel when host mismatch", %{server: server} do
      {:ok, room} = Rooms.create(server, "Alice")
      assert {:error, :forbidden} = Rooms.cancel(server, room.id, "Mallory")
      assert [_alive] = Rooms.list(server)
    end

    test "broadcasts after cancel", %{server: server} do
      {:ok, room} = Rooms.create(server, "Alice")
      assert_receive {:rooms_changed, _}
      :ok = Rooms.cancel(server, room.id, "Alice")
      assert_receive {:rooms_changed, []}
    end
  end

  describe "join/3" do
    test "removes the room and returns it", %{server: server} do
      {:ok, room} = Rooms.create(server, "Alice")
      assert {:ok, joined} = Rooms.join(server, room.id, "Bob")
      assert joined.host == "Alice"
      assert joined.guest == "Bob"
      assert [] = Rooms.list(server)
    end

    test "returns :error when room is missing", %{server: server} do
      assert {:error, :not_found} = Rooms.join(server, "MISSING", "Bob")
    end

    test "host cannot join own room", %{server: server} do
      {:ok, room} = Rooms.create(server, "Alice")
      assert {:error, :cannot_join_own_room} = Rooms.join(server, room.id, "Alice")
    end

    test "broadcasts after join", %{server: server} do
      {:ok, room} = Rooms.create(server, "Alice")
      assert_receive {:rooms_changed, _}
      {:ok, _} = Rooms.join(server, room.id, "Bob")
      assert_receive {:rooms_changed, []}
    end
  end
end
