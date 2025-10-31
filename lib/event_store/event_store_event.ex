defmodule Shared.EventStoreEvent do
  @moduledoc false
  @type event_with_metadata :: {event :: term, metadata :: map()}

  @spec wrap_for_persistence(term | list(term), Enum.t()) :: list(EventStore.EventData.t())
  def wrap_for_persistence(events, metadata) do
    events = List.wrap(events)
    metadata = Map.new(metadata)

    Enum.map(events, fn event ->
      %EventStore.EventData{
        data: event,
        metadata: metadata
      }
    end)
  end

  @spec unwrap(EventStore.RecordedEvent.t()) :: event_with_metadata
  def unwrap(%EventStore.RecordedEvent{data: domain_event, metadata: metadata} = event) do
    metadata = Map.new(metadata)

    recorded_event_metadata =
      Map.take(event, [
        :event_number,
        :event_id,
        :stream_uuid,
        :stream_version,
        :correlation_id,
        :causation_id,
        :created_at
      ])

    {domain_event, Map.merge(recorded_event_metadata, metadata)}
  end
end
