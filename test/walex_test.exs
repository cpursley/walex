defmodule WalExTest do
  use ExUnit.Case
  doctest WalEx

  test "greets the world" do
    assert WalEx.hello() == :world
  end
end
