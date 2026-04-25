defmodule ChessWeb.Components.MoveHistoryTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ChessWeb.ChessComponents, only: [move_history: 1]

  describe "move_history/1" do
    test "renders empty state when no moves" do
      html = render_component(&move_history/1, %{moves: []})
      assert html =~ "Nenhum ainda"
    end

    test "groups moves into numbered pairs" do
      moves = [
        %{from: "e2", to: "e4", color: :white},
        %{from: "e7", to: "e5", color: :black},
        %{from: "g1", to: "f3", color: :white}
      ]

      html = render_component(&move_history/1, %{moves: moves})

      assert html =~ "1."
      assert html =~ "2."
      assert html =~ "e2-e4"
      assert html =~ "e7-e5"
      assert html =~ "g1-f3"
    end

    test "highlights the latest move" do
      moves = [
        %{from: "e2", to: "e4", color: :white},
        %{from: "e7", to: "e5", color: :black}
      ]

      html = render_component(&move_history/1, %{moves: moves})

      # e7-e5 is the latest, should have the latest class
      assert html =~ ~r/data-latest="true"[^>]*>e7-e5/
    end
  end
end
