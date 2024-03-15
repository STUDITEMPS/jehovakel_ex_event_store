defmodule Shared.LoggableEventTest do
  use ExUnit.Case, async: true
  require Protocol

  defmodule EventA do
    defstruct [:a, :b, :c, :d]
  end

  defmodule EventB do
    @derive [{Shared.LoggableEvent, only: [:a, :c]}]
    defstruct [:a, :b, :c, :d]
  end

  defmodule EventC do
    @derive [{Shared.LoggableEvent, except: [:a, :c]}]
    defstruct [:a, :b, :c, :d]
  end

  defmodule EventD do
    @derive [{Shared.LoggableEvent, :all}]
    defstruct [:a, :b, :c, :d]
  end

  defmodule Strct do
    defstruct attr: :brr
  end

  describe "to_log/1" do
    test "Logs only the event name by default" do
      event = %EventA{a: "foo", b: 23, c: nil, d: %Strct{}}
      assert "EventA" == Shared.LoggableEvent.to_log(event)
    end

    test "keys to log can be defined when deriving" do
      event = %EventB{a: "foo", b: 23, c: nil, d: %Strct{}}
      assert "EventB: " <> fields = Shared.LoggableEvent.to_log(event)
      assert fields =~ "a=\"foo\""
      assert fields =~ "c=nil"
    end

    test "keys to exclude from log can be defined when deriving" do
      event = %EventC{a: "foo", b: 23, c: nil, d: %Strct{}}
      assert "EventC: " <> fields = Shared.LoggableEvent.to_log(event)
      assert fields =~ "b=23"
      assert fields =~ "d=%Shared.LoggableEventTest.Strct{attr: :brr}"
    end

    test "all keys can be included in the log when deriving" do
      event = %EventD{a: "foo", b: 23, c: nil, d: %Strct{}}
      assert "EventD: " <> fields = Shared.LoggableEvent.to_log(event)
      assert fields =~ "a=\"foo\""
      assert fields =~ "b=23"
      assert fields =~ "c=nil"
      assert fields =~ "d=%Shared.LoggableEventTest.Strct{attr: :brr}"
    end
  end
end
