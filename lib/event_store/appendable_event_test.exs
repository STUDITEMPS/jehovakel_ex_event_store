defmodule Shared.AppendableEventTest do
  use ExUnit.Case, async: true

  require Protocol

  defmodule Event do
    @moduledoc false
    defstruct [:a, :b, :c, :d]
  end

  describe "derive" do
    setup do
      {:ok, %{event: %Event{a: "a", b: "b", c: nil, d: %{foo: :bar}}}}
    end

    test "event id is a single field, streams_to_link optional", %{event: event} do
      Protocol.derive(Shared.AppendableEvent, Event, stream_id: :a)

      assert Shared.AppendableEvent.stream_id(event) == "a"
      assert Shared.AppendableEvent.streams_to_link(event) == []
    end

    test "fvent id is a single field, streams_to_link empty", %{event: event} do
      Protocol.derive(Shared.AppendableEvent, Event, stream_id: :a, streams_to_link: [])

      assert Shared.AppendableEvent.stream_id(event) == "a"
      assert Shared.AppendableEvent.streams_to_link(event) == []
    end

    test "use a single field as streams_to_link", %{event: event} do
      Protocol.derive(Shared.AppendableEvent, Event, stream_id: :a, streams_to_link: :b)

      assert Shared.AppendableEvent.stream_id(event) == "a"
      assert Shared.AppendableEvent.streams_to_link(event) == ["b"]
    end

    test "use a list as streams_to_link", %{event: event} do
      Protocol.derive(Shared.AppendableEvent, Event, stream_id: :a, streams_to_link: [:b])

      assert Shared.AppendableEvent.stream_id(event) == "a"
      assert Shared.AppendableEvent.streams_to_link(event) == ["b"]
    end

    test "Stream id needs to be present", %{event: event} do
      Protocol.derive(Shared.AppendableEvent, Event, stream_id: :c)

      assert_raise ArgumentError, "Stream ID has to be a string, got 'nil'.", fn ->
        Shared.AppendableEvent.stream_id(event)
      end
    end

    test "Stream id needs to be a string", %{event: event} do
      Protocol.derive(Shared.AppendableEvent, Event, stream_id: :d)

      assert_raise ArgumentError, "Stream ID has to be a string, got '%{foo: :bar}'.", fn ->
        Shared.AppendableEvent.stream_id(event)
      end
    end

    test "all Links need to be present", %{event: event} do
      Protocol.derive(Shared.AppendableEvent, Event, stream_id: :a, streams_to_link: :c)

      assert_raise ArgumentError,
                   "Streams ids to link need to be a string, got 'c -> nil'.",
                   fn ->
                     Shared.AppendableEvent.streams_to_link(event)
                   end
    end

    test "all links need to be strings", %{event: event} do
      Protocol.derive(Shared.AppendableEvent, Event, stream_id: :a, streams_to_link: [:c, :d])

      assert_raise ArgumentError,
                   "Streams ids to link need to be a string, got 'c -> nil, d -> %{foo: :bar}'.",
                   fn ->
                     Shared.AppendableEvent.streams_to_link(event)
                   end
    end
  end
end
