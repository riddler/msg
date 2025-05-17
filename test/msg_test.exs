defmodule MsgTest do
  use ExUnit.Case
  doctest Msg

  test "greets the world" do
    assert Msg.hello() == :world
  end
end
