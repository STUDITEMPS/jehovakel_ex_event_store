defmodule Shared.EventStoreEventTest do
  use ExUnit.Case, async: true

  alias Shared.EventStoreEvent, as: Event

  defmodule TestEvent do
    @moduledoc false
    defstruct foo: "bar"
  end

  test "wrappe in EventStore.EventData" do
    event = %TestEvent{}

    assert [%EventStore.EventData{} = event_data] =
             Event.wrap_for_persistence([event], %{
               my: "metadata",
               causation_id: "causation_id",
               correlation_id: "correlation_id"
             })

    assert event_data.data == event
    assert event_data.metadata.correlation_id == "correlation_id"
    assert event_data.metadata.my == "metadata"
    assert event_data.metadata.causation_id == "causation_id"
  end
end
