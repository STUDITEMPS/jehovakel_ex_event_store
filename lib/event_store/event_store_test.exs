defmodule Shared.EventTest do
  use Support.EventStoreCase, async: false

  @event %Shared.EventTest.FakeEvent{}
  @metadata %{meta: "data"}

  test "append event to stream" do
    assert {:ok, [%{data: @event}]} = append_event(@event, @metadata)

    assert [%EventStore.RecordedEvent{data: @event, metadata: @metadata}] =
             all_events(nil, unwrap: false)

    assert [{@event, @metadata}] = all_events()
  end

  test "append event to stream with stream_uuid" do
    assert {:ok, [%{data: @event}]} = append_event("stream_uuid", @event, @metadata)

    assert [%EventStore.RecordedEvent{data: @event, metadata: @metadata}] =
             all_events(nil, unwrap: false)

    assert [{@event, @metadata}] = all_events()
    assert [{@event, @metadata}] = all_events("stream_uuid")
  end

  test "append list of events" do
    assert {:ok, [%{data: @event}]} = append_event([@event], @metadata)

    assert [%EventStore.RecordedEvent{data: @event, metadata: @metadata}] =
             all_events(nil, unwrap: false)

    assert [{@event, @metadata}] = all_events()
  end
end
