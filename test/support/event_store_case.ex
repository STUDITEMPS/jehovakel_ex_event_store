defmodule Support.EventStoreCase do
  @moduledoc """
  Used for Tests using event store
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import JehovakelEx.EventStore,
        only: [
          append_event: 2,
          append_event: 3,
          all_events: 2,
          all_events: 1,
          all_events: 0,
          find_event: 1
        ],
        warn: false

      def wait_until(fun), do: wait_until(500, fun)

      def wait_until(0, fun), do: fun.()

      def wait_until(timeout, fun) do
        try do
          fun.()
        rescue
          ExUnit.AssertionError ->
            :timer.sleep(100)
            wait_until(max(0, timeout - 100), fun)
        end
      end
    end
  end

  setup _tags do
    # reset eventstore
    config = EventStore.Config.parsed(JehovakelEx.EventStore, :jehovakel_ex_event_store)

    {:ok, eventstore_connection} =
      config
      |> EventStore.Config.default_postgrex_opts()
      |> Postgrex.start_link()

    EventStore.Storage.Initializer.reset!(eventstore_connection, config)

    {:ok, _} = Application.ensure_all_started(:eventstore)

    start_supervised!(JehovakelEx.EventStore)
    start_supervised!(Support.Repo)

    on_exit(fn ->
      # stop eventstore application
      Application.stop(:eventstore)
      Process.exit(eventstore_connection, :shutdown)
    end)

    {:ok, %{postgrex_connection: eventstore_connection}}
  end
end
