defmodule ChessWeb.Components.BoardTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ChessWeb.ChessComponents, only: [board: 1]

  defp initial_pieces do
    %{
      "a1" => {:white, :rook},
      "b1" => {:white, :knight},
      "e1" => {:white, :king},
      "e8" => {:black, :king},
      "d2" => {:white, :pawn},
      "e7" => {:black, :pawn}
    }
  end

  describe "board/1" do
    test "renders 64 squares" do
      html =
        render_component(&board/1, %{
          pieces: %{},
          orientation: :white,
          selected: nil,
          legal_targets: []
        })

      assert html |> String.split(~s(data-square=)) |> length() == 65
    end

    test "renders pieces using unicode glyphs" do
      html =
        render_component(&board/1, %{
          pieces: initial_pieces(),
          orientation: :white,
          selected: nil,
          legal_targets: []
        })

      # White king on e1 -> ♔
      assert html =~ "♔"
      # Black king on e8 -> ♚
      assert html =~ "♚"
      # White pawn on d2 -> ♙
      assert html =~ "♙"
    end

    test "white orientation: a8 is in the top-left, h1 in the bottom-right" do
      html =
        render_component(&board/1, %{
          pieces: %{},
          orientation: :white,
          selected: nil,
          legal_targets: []
        })

      first_square = extract_first_square(html)
      last_square = extract_last_square(html)

      assert first_square == "a8"
      assert last_square == "h1"
    end

    test "black orientation: h1 is in the top-left, a8 in the bottom-right" do
      html =
        render_component(&board/1, %{
          pieces: %{},
          orientation: :black,
          selected: nil,
          legal_targets: []
        })

      assert extract_first_square(html) == "h1"
      assert extract_last_square(html) == "a8"
    end

    test "highlights selected square and legal targets" do
      html =
        render_component(&board/1, %{
          pieces: initial_pieces(),
          orientation: :white,
          selected: "d2",
          legal_targets: ["d3", "d4"]
        })

      assert html =~ ~s(data-selected="true")
      assert html =~ ~s(data-target="true")
      # exactly two targets
      assert html |> String.split(~s(data-target="true")) |> length() == 3
    end

    test "each square is a phx-click button with phx-value-square" do
      html =
        render_component(&board/1, %{
          pieces: %{},
          orientation: :white,
          selected: nil,
          legal_targets: []
        })

      assert html =~ ~s(phx-click="select_square")
      assert html =~ ~s(phx-value-square="e4")
    end
  end

  defp extract_first_square(html) do
    Regex.run(~r/data-square="([a-h][1-8])"/, html, capture: :all_but_first)
    |> List.first()
  end

  defp extract_last_square(html) do
    Regex.scan(~r/data-square="([a-h][1-8])"/, html, capture: :all_but_first)
    |> List.last()
    |> List.first()
  end
end
