defmodule ChessWeb.UiComponents do
  @moduledoc """
  Reusable UI primitives for the Chess Club app.

  Themed for the warm cream + green Chess Club design. Used across
  login, lobby, and game screens.
  """
  use Phoenix.Component

  @btn_base "inline-flex items-center justify-center gap-2 rounded-md font-medium font-serif tracking-[0.01em] transition whitespace-nowrap disabled:opacity-45 disabled:cursor-not-allowed"

  @btn_variants %{
    "primary" =>
      "bg-accent text-white hover:bg-accent2 hover:-translate-y-px hover:shadow-[0_4px_14px_rgba(61,107,79,.25)] px-6 py-3 text-[15px]",
    "ghost" =>
      "bg-transparent text-text border border-border2 hover:bg-surface2 px-6 py-3 text-[15px]",
    "outline" =>
      "bg-transparent text-accent border border-accent/25 hover:bg-accent/10 px-6 py-3 text-[15px]",
    "danger" =>
      "bg-transparent text-warn border border-warn/30 hover:bg-warn/10 px-4 py-2 text-[13px]",
    "solo" => "bg-surface2 text-warm border border-warm/25 hover:bg-warm/10 px-6 py-3 text-[15px]"
  }

  attr :variant, :string, default: "primary", values: Map.keys(@btn_variants)
  attr :type, :string, default: "button"
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(name value form phx-click phx-submit phx-disable-with id)
  slot :inner_block, required: true

  def btn(assigns) do
    assigns =
      assign(assigns,
        variant_class: Map.fetch!(@btn_variants, assigns.variant),
        base: @btn_base
      )

    ~H"""
    <button
      type={@type}
      disabled={@disabled}
      class={[@base, @variant_class, @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :name, :string, required: true
  attr :size, :string, default: "default", values: ~w(sm default)

  def avatar(assigns) do
    classes =
      case assigns.size do
        "sm" -> "w-7 h-7 text-[13px]"
        "default" -> "w-9 h-9 text-[15px]"
      end

    initial =
      assigns.name
      |> String.first()
      |> Kernel.||("?")
      |> String.upcase()

    assigns = assign(assigns, classes: classes, initial: initial)

    ~H"""
    <div class={[
      "shrink-0 rounded-full bg-accent/10 border border-accent/25",
      "flex items-center justify-center font-display font-bold text-accent tracking-[.03em]",
      @classes
    ]}>
      <span>{@initial}</span>
    </div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={[
      "bg-surface border border-border rounded-[10px] px-5 py-[18px]",
      "shadow-[0_1px_6px_rgba(44,40,32,.04)]",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  slot :inner_block, required: true

  def card_label(assigns) do
    ~H"""
    <div class="text-[10px] uppercase tracking-[.14em] text-faint mb-2.5 font-semibold">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :name, :string, required: true
  attr :placeholder, :string, default: nil
  attr :value, :string, default: ""
  attr :type, :string, default: "text"
  attr :maxlength, :integer, default: nil
  attr :autofocus, :boolean, default: false
  attr :error, :string, default: nil
  attr :rest, :global

  def text_input(assigns) do
    ~H"""
    <div class="flex flex-col gap-1">
      <input
        type={@type}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        maxlength={@maxlength}
        autofocus={@autofocus}
        class={[
          "w-full bg-surface border rounded-md px-4 py-3 text-[15px] font-serif text-text",
          "outline-none transition placeholder:text-faint",
          "focus:border-accent focus:ring-2 focus:ring-accent/20",
          if(@error, do: "border-warn", else: "border-border2")
        ]}
        {@rest}
      />
      <p :if={@error} class="text-warn text-[13px]">{@error}</p>
    </div>
    """
  end

  slot :inner_block, required: true

  def section_label(assigns) do
    ~H"""
    <div class="text-[11px] uppercase tracking-[.14em] text-faint font-serif font-semibold mb-3.5">
      {render_slot(@inner_block)}
    </div>
    """
  end

  slot :inner_block, required: true

  def divider(assigns) do
    ~H"""
    <hr class="border-0 border-t border-border my-7" />
    """
  end
end
