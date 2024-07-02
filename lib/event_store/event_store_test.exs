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

  test "find event by event_id" do
    {:ok, _} = append_event("stream_uuid", @event, @metadata)
    [%EventStore.RecordedEvent{event_id: event_id}] = all_events(nil, unwrap: false)

    assert {:ok, {@event, %{event_id: ^event_id}}} = find_event(event_id)
  end

  test "uses a shared db connection, so we can wrap append_event in a transaction" do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:append_event, fn _, _ ->
      append_event(@event, @metadata)
    end)
    |> Ecto.Multi.run(:force_rollback, fn _, _ ->
      {:error, :rollback_transaction}
    end)
    |> Support.Repo.transaction()

    assert [] = all_events()
  end
end
