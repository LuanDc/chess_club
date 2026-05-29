defmodule Chess.GameEngine do
  @moduledoc """
  GenServer wrapper around the binbo chess engine. Owns the underlying
  binbo pid and self-heals if it crashes: records every move and any
  manually-set winner, and on `:DOWN` starts a fresh binbo and replays
  the recorded history so callers see a stable engine pid throughout.
  """
  use GenServer

  @type color :: :white | :black
  @type piece :: :pawn | :knight | :bishop | :rook | :queen | :king
  @type status ::
          :in_progress
          | {:checkmate, :white_wins | :black_wins}
          | {:draw, atom()}
          | {:winner, color(), term()}

  ## Client API

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  @doc "Back-compat alias for `start_link/0`."
  def new, do: start_link()

  def stop(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid)
    :ok
  end

  def fen(pid), do: GenServer.call(pid, :fen)
  def side_to_move(pid), do: GenServer.call(pid, :side_to_move)
  def status(pid), do: GenServer.call(pid, :status)
  def pieces(pid), do: GenServer.call(pid, :pieces)
  def legal_moves_from(pid, sq), do: GenServer.call(pid, {:legal_moves_from, sq})
  def legal_moves(pid), do: GenServer.call(pid, :legal_moves)

  def move(pid, from, to, promotion \\ nil),
    do: GenServer.call(pid, {:move, from, to, promotion})

  def set_winner(pid, color, reason),
    do: GenServer.call(pid, {:set_winner, color, reason})

  ## Server callbacks

  @impl true
  def init(_opts) do
    case start_binbo() do
      {:ok, binbo} ->
        ref = Process.monitor(binbo)
        {:ok, %{binbo: binbo, monitor: ref, moves: [], winner: nil}}

      {:error, _} = err ->
        {:stop, err}
    end
  end

  @impl true
  def handle_call(:fen, _from, state) do
    {:ok, fen} = :binbo.get_fen(state.binbo)
    {:reply, to_string(fen), state}
  end

  def handle_call(:side_to_move, _from, state) do
    {:ok, color} = :binbo.side_to_move(state.binbo)
    {:reply, color, state}
  end

  def handle_call(:status, _from, state) do
    {:ok, raw} = :binbo.game_status(state.binbo)
    {:reply, normalize_status(raw), state}
  end

  def handle_call(:pieces, _from, state) do
    {:ok, list} = :binbo.get_pieces_list(state.binbo, :notation)

    pieces =
      Enum.reduce(list, %{}, fn {sq, color, piece}, acc ->
        Map.put(acc, to_string(sq), {color, piece})
      end)

    {:reply, pieces, state}
  end

  def handle_call({:legal_moves_from, from}, _from, state) do
    moves =
      state.binbo
      |> normalized_legal_moves()
      |> Enum.flat_map(fn
        {^from, to} -> [to]
        {^from, to, _promo} -> [to]
        _ -> []
      end)
      |> Enum.uniq()

    {:reply, moves, state}
  end

  def handle_call(:legal_moves, _from, state) do
    grouped =
      state.binbo
      |> normalized_legal_moves()
      |> Enum.reduce(%{}, fn
        {from, to}, acc -> Map.update(acc, from, [to], &[to | &1])
        {from, to, _promo}, acc -> Map.update(acc, from, [to], &[to | &1])
      end)
      |> Map.new(fn {from, tos} -> {from, tos |> Enum.uniq() |> Enum.reverse()} end)

    {:reply, grouped, state}
  end

  def handle_call({:move, from, to, promo}, _from, state) do
    case apply_move(state.binbo, from, to, promo) do
      {:ok, status} ->
        new_state = %{state | moves: state.moves ++ [{from, to, promo}]}
        {:reply, {:ok, status}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_winner, color, reason}, _from, state) do
    case :binbo.set_game_winner(state.binbo, color, reason) do
      :ok -> {:reply, :ok, %{state | winner: {color, reason}}}
      err -> {:reply, err, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{monitor: ref} = state) do
    with {:ok, new_binbo} <- start_binbo(),
         :ok <- replay_moves(new_binbo, state.moves),
         :ok <- maybe_restore_winner(new_binbo, state.winner) do
      new_ref = Process.monitor(new_binbo)
      {:noreply, %{state | binbo: new_binbo, monitor: new_ref}}
    else
      _ -> {:stop, :binbo_reconstruction_failed, state}
    end
  end

  ## Private helpers

  defp start_binbo do
    with {:ok, pid} <- :binbo.new_server(),
         {:ok, _} <- :binbo.new_game(pid) do
      {:ok, pid}
    end
  end

  defp apply_move(binbo, from, to, promo) do
    move_str = from <> to <> promotion_suffix(promo)

    case :binbo.move(binbo, move_str) do
      {:ok, raw} -> {:ok, normalize_status(raw)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay_moves(_binbo, []), do: :ok

  defp replay_moves(binbo, [{from, to, promo} | rest]) do
    case apply_move(binbo, from, to, promo) do
      {:ok, _} -> replay_moves(binbo, rest)
      err -> err
    end
  end

  defp maybe_restore_winner(_binbo, nil), do: :ok

  defp maybe_restore_winner(binbo, {color, reason}),
    do: :binbo.set_game_winner(binbo, color, reason)

  defp normalized_legal_moves(binbo) do
    case :binbo.all_legal_moves(binbo, :str) do
      {:ok, moves} -> Enum.map(moves, &normalize_move/1)
      {:error, _} -> []
    end
  end

  defp normalize_move({from, to}), do: {to_str(from), to_str(to)}
  defp normalize_move({from, to, promo}), do: {to_str(from), to_str(to), promo}

  defp to_str(charlist) when is_list(charlist), do: List.to_string(charlist)
  defp to_str(bin) when is_binary(bin), do: bin

  defp promotion_suffix(nil), do: ""
  defp promotion_suffix(:queen), do: "q"
  defp promotion_suffix(:rook), do: "r"
  defp promotion_suffix(:bishop), do: "b"
  defp promotion_suffix(:knight), do: "n"

  defp normalize_status(:continue), do: :in_progress
  defp normalize_status({:checkmate, who}), do: {:checkmate, who}
  defp normalize_status({:draw, why}), do: {:draw, why}
  defp normalize_status({:winner, winner, {:manual, why}}), do: {:winner, winner, why}
end
