defmodule Shared.EventStoreEvent do
  @type event_with_metadata :: {event :: term, metadata :: map()}

  @spec wrap_for_persistence(event :: term | events :: list(term), metadata :: Enum.t()) ::
          list(EventStore.EventData.t())
  def wrap_for_persistence(events, metadata) do
    events = List.wrap(events)
    metadata = Enum.into(metadata, %{})

    Enum.map(events, fn event ->
      %EventStore.EventData{
        data: event,
        metadata: metadata
      }
    end)
  end

  @spec unwrap(EventStore.RecordedEvent.t()) :: event_with_metadata
  def unwrap(%EventStore.RecordedEvent{data: domain_event, metadata: metadata} = event) do
    metadata = Enum.into(metadata, %{})

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
