defmodule ChessWeb.ChessComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ChessWeb.ChessComponents

  alias Chess.Rooms.Room

  describe "navbar/1" do
    test "renders the Chess Club brand" do
      html = render_component(&navbar/1, %{right: [%{__slot__: :right, inner_block: fn _, _ -> "" end}]})
      assert html =~ "Chess Club"
      assert html =~ "♚"
    end

    test "renders the right slot content" do
      html =
        render_component(&navbar/1, %{
          right: [%{__slot__: :right, inner_block: fn _, _ -> "Sair" end}]
        })

      assert html =~ "Sair"
    end
  end

  describe "empty_state/1" do
    test "renders glyph, title and description" do
      html =
        render_component(&empty_state/1, %{
          glyph: "⌧",
          title: "Nada por aqui",
          description: "Crie a primeira sala"
        })

      assert html =~ "⌧"
      assert html =~ "Nada por aqui"
      assert html =~ "Crie a primeira sala"
    end
  end

  describe "tip_bar/1" do
    test "renders inner block" do
      html =
        render_component(&tip_bar/1, %{
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Dica" end}]
        })

      assert html =~ "Dica"
    end
  end

  describe "room_card/1" do
    test "with mine? true shows 'Sua sala' and the room id tag" do
      room = %Room{id: "ABC123", host: "Alice", inserted_at: 0}
      html = render_component(&room_card/1, %{room: room, mine?: true})

      assert html =~ "Sua sala"
      assert html =~ "#ABC123"
      refute html =~ "Entrar"
    end

    test "with mine? false shows host name and Entrar button" do
      room = %Room{id: "XYZ789", host: "Bob", inserted_at: 0}
      html = render_component(&room_card/1, %{room: room, mine?: false})

      assert html =~ "Bob"
      assert html =~ "Entrar"
      assert html =~ ~s(phx-value-room-id="XYZ789")
    end
  end
end
