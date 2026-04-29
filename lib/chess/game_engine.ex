defmodule Chess.GameEngine do
  @moduledoc """
  Thin wrapper around the binbo chess engine. Owns a binbo server pid
  and exposes an Elixir-flavoured API: starts in the initial position,
  validates moves, returns FEN, status, and legal moves.

  All public functions normalize binbo's Erlang atoms / tuples / binaries
  into Elixir-friendly shapes so the rest of the app does not depend on
  binbo directly.
  """

  @type color :: :white | :black
  @type piece :: :pawn | :knight | :bishop | :rook | :queen | :king
  @type status ::
          :in_progress
          | {:checkmate, :white_wins | :black_wins}
          | {:draw, atom()}
          | {:winner, color(), term()}

  @doc "Starts a fresh game in the initial position."
  @spec new() :: {:ok, pid()} | {:error, term()}
  def new do
    case :binbo.new_server() do
      {:ok, pid} ->
        case :binbo.new_game(pid) do
          {:ok, _status} -> {:ok, pid}
          err -> err
        end

      err ->
        err
    end
  end

  @doc "Stops the underlying binbo server."
  @spec stop(pid()) :: :ok
  def stop(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      :binbo.stop_server(pid)
    end

    :ok
  end

  @doc "Returns the current FEN as a string."
  @spec fen(pid()) :: String.t()
  def fen(pid) do
    {:ok, fen} = :binbo.get_fen(pid)
    to_string(fen)
  end

  @doc "Whose turn it is, `:white` or `:black`."
  @spec side_to_move(pid()) :: color()
  def side_to_move(pid) do
    {:ok, color} = :binbo.side_to_move(pid)
    color
  end

  @doc """
  Attempts to play a move from `from` to `to` (e.g. "e2" -> "e4"),
  optionally with a promotion piece (`:queen`, `:rook`, `:bishop`,
  `:knight`). Returns `{:ok, status}` or `{:error, reason}`.
  """
  @spec move(pid(), String.t(), String.t(), piece() | nil) ::
          {:ok, status()} | {:error, term()}
  def move(pid, from, to, promotion \\ nil) do
    move_str = from <> to <> promotion_suffix(promotion)

    case :binbo.move(pid, move_str) do
      {:ok, status} -> {:ok, normalize_status(status)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Returns the current game status as an Elixir term."
  @spec status(pid()) :: status()
  def status(pid) do
    {:ok, status} = :binbo.game_status(pid)
    normalize_status(status)
  end

  @doc """
  Returns the legal target squares for the piece on `from`, or `[]`
  if the square is empty / not the side-to-move's piece.
  """
  @spec legal_moves_from(pid(), String.t()) :: [String.t()]
  def legal_moves_from(pid, from) do
    pid
    |> normalized_legal_moves()
    |> Enum.flat_map(fn
      {^from, to} -> [to]
      {^from, to, _promo} -> [to]
      _ -> []
    end)
    |> Enum.uniq()
  end

  @doc "Map of every legal move grouped by source square."
  @spec legal_moves(pid()) :: %{String.t() => [String.t()]}
  def legal_moves(pid) do
    pid
    |> normalized_legal_moves()
    |> Enum.reduce(%{}, fn
      {from, to}, acc -> Map.update(acc, from, [to], &[to | &1])
      {from, to, _promo}, acc -> Map.update(acc, from, [to], &[to | &1])
    end)
    |> Map.new(fn {from, tos} -> {from, tos |> Enum.uniq() |> Enum.reverse()} end)
  end

  defp normalized_legal_moves(pid) do
    case :binbo.all_legal_moves(pid, :str) do
      {:ok, moves} -> Enum.map(moves, &normalize_move/1)
      {:error, _} -> []
    end
  end

  defp normalize_move({from, to}), do: {to_str(from), to_str(to)}
  defp normalize_move({from, to, promo}), do: {to_str(from), to_str(to), promo}

  defp to_str(charlist) when is_list(charlist), do: List.to_string(charlist)
  defp to_str(bin) when is_binary(bin), do: bin

  @doc """
  Map of every occupied square to its piece, e.g.:

      %{"e1" => {:white, :king}, ...}
  """
  @spec pieces(pid()) :: %{String.t() => {color(), piece()}}
  def pieces(pid) do
    {:ok, list} = :binbo.get_pieces_list(pid, :notation)

    Enum.reduce(list, %{}, fn {sq, color, piece}, acc ->
      Map.put(acc, to_string(sq), {color, piece})
    end)
  end

  @doc """
  Force a winner (used when a player resigns). `reason` is opaque metadata
  attached to the status, e.g. `:resign`.
  """
  @spec set_winner(pid(), color(), term()) :: :ok | {:error, term()}
  def set_winner(pid, color, reason) do
    :binbo.set_game_winner(pid, color, reason)
  end

  ## Helpers

  defp promotion_suffix(nil), do: ""
  defp promotion_suffix(:queen), do: "q"
  defp promotion_suffix(:rook), do: "r"
  defp promotion_suffix(:bishop), do: "b"
  defp promotion_suffix(:knight), do: "n"

  defp normalize_status(:continue), do: :in_progress
  defp normalize_status({:checkmate, who}), do: {:checkmate, who}
  defp normalize_status({:draw, why}), do: {:draw, why}
  defp normalize_status({:winner, winner, {:manual, why}}), do: {:winner, winner, why}
  defp normalize_status({:winner, winner, why}), do: {:winner, winner, why}
  defp normalize_status(other), do: other
end
