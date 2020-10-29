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

    assert "Event: a=\"foo\" b=23 c=nil d=%Shared.LoggableEventTest.Strct{attr: :brr}" ==
             Shared.LoggableEvent.to_log(event)
  end
end
