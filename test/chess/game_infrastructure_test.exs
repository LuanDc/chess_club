defmodule Chess.GameInfrastructureTest do
  use ExUnit.Case, async: false

  describe "supervision tree" do
    test "is a child of the application supervisor" do
      children = Supervisor.which_children(Chess.Supervisor)
      names = Enum.map(children, fn {name, _, _, _} -> name end)
      assert Chess.GameInfrastructure in names
    end

    test "supervises Rooms, game registries, and GameSupervisor" do
      children = Supervisor.which_children(Chess.GameInfrastructure)
      names = Enum.map(children, fn {name, _, _, _} -> name end)
      assert Chess.Rooms in names
      assert Chess.GameRegistry in names
      assert Chess.GameInstanceRegistry in names
      assert Chess.GameSupervisor in names
    end
  end
end
