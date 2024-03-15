defmodule Shared.LoggableEventTest do
  use ExUnit.Case, async: true
  require Protocol

  defmodule Event do
    defstruct [:a, :b, :c, :d]
  end

  defmodule Strct do
    defstruct attr: :brr
  end

  test "to_log/1" do
    event = %Event{a: "foo", b: 23, c: nil, d: %Strct{}}

    assert "Event: " <> log_body = Shared.LoggableEvent.to_log(event)
    assert log_body =~ "a=\"foo\""
    assert log_body =~ "b=23"
    assert log_body =~ "c=nil"
    assert log_body =~ "d=%Shared.LoggableEventTest.Strct{attr: :brr}"
  end
end
