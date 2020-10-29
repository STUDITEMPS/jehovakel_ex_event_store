defmodule Shared.EventStoreListenerTest do
  use Support.EventStoreCase, async: false
  import ExUnit.CaptureLog

  @event %Shared.EventTest.FakeEvent{}

  defmodule EventHandlingError do
    defexception [:message]
  end

  defmodule Counter do
    use Agent

    def start_link(initial_value) do
      Agent.start_link(fn -> initial_value end, name: __MODULE__)
    end

    def increment do
      Agent.get_and_update(__MODULE__, &{&1, &1 + 1})
    end
  end

  defmodule ExampleConsumer do
    use Shared.EventStoreListener,
      subscription_key: "example_consumer",
      event_store: JehovakelEx.EventStore

    def handle(_event, %{test_pid: test_pid, raise_until: raise_until}) do
      case Counter.increment() do
        count when count <= raise_until ->
          send(test_pid, :exception_during_event_handling)
          raise EventHandlingError, "BAM BAM BAM"

        _ ->
          send(test_pid, :event_handled_successfully)
      end

      :ok
    end
  end

  setup do
    old_log_level = Logger.level()
    Logger.configure(level: :warn)

    start_supervised!(ExampleConsumer)
    {:ok, _pid} = Counter.start_link(0)

    on_exit fn ->
      Logger.configure(level: old_log_level)
    end
    :ok
  end

  describe "Retry" do
    test "automatically on Exception during event handling without GenServer restart" do
      capture_log([level: :warn], fn ->
        {:ok, _events} =
          JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 0})

        assert_receive :exception_during_event_handling, 500
        assert_receive :event_handled_successfully, 500
      end)
    end

    test "does not restart Listener process" do
      capture_log([level: :warn], fn ->
        listener_pid = Process.whereis(ExampleConsumer)

        {:ok, _events} =
          JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 0})

        assert_receive :event_handled_successfully, 500
        assert listener_pid == Process.whereis(ExampleConsumer)
      end)
    end

    test "stops EventStoreListener GenServer after 3 attempts" do
      logs =
        capture_log([level: :warn], fn ->
          listener_pid = Process.whereis(ExampleConsumer)

          {:ok, _events} =
            JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 3})

          assert_receive :exception_during_event_handling
          assert_receive :event_handled_successfully, 500

          assert listener_pid != Process.whereis(ExampleConsumer)
        end)

      assert logs =~ "ExampleConsumer is retrying (1/3)"
      assert logs =~ "ExampleConsumer is retrying (2/3)"
      assert logs =~ "ExampleConsumer is retrying (3/3)"
      assert logs =~ "is dying due to bad event after 3 retries"
    end
  end

  test "Log Stacktrace on failing to handle exception during event handling" do
    logs =
      capture_log([level: :warn], fn ->
        {:ok, _events} =
          JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 4})

        assert_receive :exception_during_event_handling
        assert_receive :event_handled_successfully, 500
      end)

    assert logs =~ "Stacktrace"
    assert logs =~ "BAM BAM BAM"
    assert logs =~ "Shared.EventStoreListenerTest.ExampleConsumer"
    assert logs =~ "lib/event_store/event_store_listener_test.exs"
  end
end
