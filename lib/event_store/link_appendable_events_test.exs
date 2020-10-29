defmodule Shared.LinkAppendableEventsTest do
  use Support.EventStoreCase, async: false

  defmodule TestEvent do
    @derive {Shared.AppendableEvent, stream_id: :a, streams_to_link: :b}
    defstruct [:a, :b, :c, :d]
  end

  setup do
    event = %TestEvent{a: "id_a", b: "id_b", c: "some_value_for_c", d: :something}

    start_supervised!({Shared.LinkAppendableEvents, event_store: JehovakelEx.EventStore})

    {:ok, %{event: event}}
  end

  test "link an event to the streams defined in AppendableEvent", %{event: event} do
    assert {:ok, _event_data} = JehovakelEx.EventStore.append_event(event, _metadata = %{})

    wait_until(fn ->
      assert [{^event, metadata}] = all_events("id_a")
      assert [{^event, metadata}] = all_events("id_b")
    end)
  end

  test "link an event to the stream twice does not produce errors", %{
    event: event,
    postgrex_connection: postgrex
  } do
    assert {:ok, _event_data} = JehovakelEx.EventStore.append_event(event, _metadata = %{})

    wait_until(fn ->
      assert [{^event, metadata}] = all_events("id_a")
      assert [{^event, metadata}] = all_events("id_b")
    end)

    # Simulate linking running twice
    assert :ok = stop_supervised(Shared.LinkAppendableEvents)

    Postgrex.query!(postgrex, "DELETE FROM subscriptions WHERE true", [])

    start_supervised!(
      {Shared.LinkAppendableEvents, event_store: JehovakelEx.EventStore, subscription_name: "FOO"}
    )

    wait_until(fn ->
      assert %{num_rows: 1, rows: [[1]]} =
               Postgrex.query!(
                 postgrex,
                 "SELECT last_seen FROM subscriptions WHERE subscription_name='FOO'",
                 []
               )
    end)
  end
end
