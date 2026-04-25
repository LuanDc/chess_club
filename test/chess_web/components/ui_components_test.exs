defmodule ChessWeb.UiComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ChessWeb.UiComponents

  describe "btn/1" do
    test "renders primary variant by default" do
      html = render_component(&btn/1, %{inner_block: slot("Entrar")})

      assert html =~ "Entrar"
      assert html =~ "bg-accent"
    end

    test "applies ghost variant" do
      html = render_component(&btn/1, %{variant: "ghost", inner_block: slot("Sair")})
      assert html =~ "border-border2"
      refute html =~ "bg-accent "
    end

    test "applies outline variant" do
      html = render_component(&btn/1, %{variant: "outline", inner_block: slot("Entrar →")})
      assert html =~ "text-accent"
      assert html =~ "border"
    end

    test "applies danger variant" do
      html = render_component(&btn/1, %{variant: "danger", inner_block: slot("Desistir")})
      assert html =~ "text-warn"
    end

    test "applies solo variant" do
      html = render_component(&btn/1, %{variant: "solo", inner_block: slot("Jogar Sozinho")})
      assert html =~ "text-warm"
    end

    test "respects disabled and propagates rest attrs" do
      html =
        render_component(&btn/1, %{
          disabled: true,
          rest: %{"phx-click": "go", id: "submit-btn"},
          inner_block: slot("Go")
        })

      assert html =~ ~s(disabled)
      assert html =~ ~s(phx-click="go")
      assert html =~ ~s(id="submit-btn")
    end
  end

  describe "avatar/1" do
    test "renders uppercase initial of the name" do
      html = render_component(&avatar/1, %{name: "alice"})
      assert html =~ ">A<"
    end

    test "small size applies sm classes" do
      html = render_component(&avatar/1, %{name: "Bob", size: "sm"})
      assert html =~ "w-7"
    end

    test "default size applies larger box" do
      html = render_component(&avatar/1, %{name: "Bob"})
      assert html =~ "w-9"
    end
  end

  describe "card/1" do
    test "renders inner block inside surface card" do
      html = render_component(&card/1, %{inner_block: slot("conteudo")})
      assert html =~ "conteudo"
      assert html =~ "bg-surface"
      assert html =~ "border"
    end
  end

  describe "card_label/1" do
    test "renders uppercase label" do
      html = render_component(&card_label/1, %{inner_block: slot("Status")})
      assert html =~ "Status"
      assert html =~ "uppercase"
    end
  end

  describe "text_input/1" do
    test "renders input with name, placeholder and value" do
      html =
        render_component(&text_input/1, %{
          name: "nickname",
          placeholder: "Apelido",
          value: "alice"
        })

      assert html =~ ~s(name="nickname")
      assert html =~ ~s(placeholder="Apelido")
      assert html =~ ~s(value="alice")
    end

    test "shows error message when error is given" do
      html =
        render_component(&text_input/1, %{
          name: "nickname",
          error: "Use pelo menos 2 caracteres."
        })

      assert html =~ "Use pelo menos 2 caracteres."
      assert html =~ "text-warn"
    end

    test "without error does not render error block" do
      html = render_component(&text_input/1, %{name: "nickname"})
      refute html =~ "text-warn"
    end
  end

  describe "section_label/1" do
    test "renders uppercase tracked label" do
      html = render_component(&section_label/1, %{inner_block: slot("Salas abertas")})
      assert html =~ "Salas abertas"
      assert html =~ "uppercase"
    end
  end

  defp slot(text) do
    [%{__slot__: :inner_block, inner_block: fn _, _ -> text end}]
  end
end
