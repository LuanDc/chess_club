defmodule ChessWeb.LoginLive do
  use ChessWeb, :live_view

  @min_length 2
  @max_length 20

  @impl true
  def mount(_params, session, socket) do
    case session["nickname"] do
      nickname when is_binary(nickname) and byte_size(nickname) > 0 ->
        {:ok, push_navigate(socket, to: ~p"/lobby")}

      _ ->
        {:ok,
         socket
         |> assign(
           nickname: "",
           error: nil,
           valid?: false,
           max_length: @max_length
         )}
    end
  end

  @impl true
  def handle_event("validate", %{"nickname" => raw}, socket) do
    nickname = raw |> to_string() |> String.slice(0, @max_length)
    trimmed = String.trim(nickname)

    {error, valid?} =
      cond do
        trimmed == "" -> {nil, false}
        String.length(trimmed) < @min_length -> {"Use pelo menos #{@min_length} caracteres.", false}
        true -> {nil, true}
      end

    {:noreply, assign(socket, nickname: nickname, error: error, valid?: valid?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center px-5 bg-[radial-gradient(ellipse_70%_40%_at_20%_80%,rgba(61,107,79,.06)_0%,transparent_70%),radial-gradient(ellipse_50%_60%_at_80%_10%,rgba(139,94,60,.05)_0%,transparent_60%)]">
      <div class="bg-surface border border-border rounded-2xl px-12 py-14 w-[440px] max-w-full text-center shadow-[0_2px_24px_rgba(44,40,32,.06)] animate-fade-up">
        <span class="font-display text-[64px] leading-none text-accent block mb-5">♚</span>
        <h1 class="font-display text-[38px] font-bold text-text mb-2 tracking-[.02em]">Chess Club</h1>
        <p class="text-muted text-[15px] mb-9 leading-[1.65] italic">
          Desafie amigos em partidas ao vivo.<br />Realtime via Phoenix PubSub.
        </p>

        <form
          id="login-form"
          action={~p"/session"}
          method="post"
          phx-change="validate"
          class="flex flex-col gap-3"
        >
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <div class="text-left text-[13px] text-muted -mb-1.5 tracking-[.04em]">Seu apelido</div>
          <.text_input
            name="nickname"
            placeholder="Como devemos chamá-lo?"
            value={@nickname}
            maxlength={@max_length}
            autofocus={true}
            error={@error}
          />
          <.btn type="submit" variant="primary" disabled={!@valid?} class="mt-2">
            Entrar no Lobby →
          </.btn>
        </form>
      </div>
    </div>
    """
  end
end
