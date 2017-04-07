defmodule Logger.Backends.RsyslogTest do
  use ExUnit.Case
  require Logger
  
  doctest Logger.Backends.Rsyslog

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "log" do
    Logger.debug("test")
  end
end
