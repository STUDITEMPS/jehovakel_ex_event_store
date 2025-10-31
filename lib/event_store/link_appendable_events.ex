defmodule Shared.LinkAppendableEvents do
  @moduledoc false

  use GenServer

  def child_spec(opts) do
    start_options = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }

    Supervisor.child_spec(start_options, [])
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  # Opts are all options available for EventStore.subscribe_to_all_streams/3
  def init(opts) do
    event_store = Keyword.fetch!(opts, :event_store)

    {subscription_name, opts} = Keyword.get_and_update(opts, :subscription_name, fn _ -> :pop end)
    subscription_name = subscription_name || "__jehovakel_ex_event_store_link_appendable_events__"
    # Subscribe to events from all streams
    {:ok, subscription} = event_store.subscribe_to_all_streams(subscription_name, self(), opts)

    {:ok, %{event_store: event_store, subscription: subscription}}
  end

  # Successfully subscribed to all streams
  def handle_info({:subscribed, subscription}, %{subscription: subscription} = state) do
    {:noreply, state}
  end

  # Event notification
  def handle_info({:events, events}, %{subscription: subscription, event_store: event_store} = state) do
    link_appendable_events(event_store, subscription, events)

    {:noreply, state}
  end

  defp link_appendable_events(event_store, subscription, events) do
    for event <- events do
      link_appendable_event(event_store, subscription, event)
    end
  end

  defp link_appendable_event(event_store, subscription, %EventStore.RecordedEvent{} = eventstore_event) do
    event = eventstore_event.data

    if Shared.AppendableEvent.impl_for(event) do
      streams_to_link = Shared.AppendableEvent.streams_to_link(event)

      for stream <- streams_to_link do
        :ok = link_appendable_event(event_store, eventstore_event, stream)
      end
    end

    # Confirm receipt of received events
    :ok = event_store.ack(subscription, eventstore_event)
  end

  defp link_appendable_event(event_store, %EventStore.RecordedEvent{} = event, stream_id) do
    case event_store.link_to_stream(stream_id, :any_version, [event]) do
      :ok -> :ok
      {:error, :duplicate_event} -> :ok
      error -> error
    end
  end
end
