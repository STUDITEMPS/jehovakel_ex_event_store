defmodule Shared.EventStoreListenerTest do
  use Support.EventStoreCase, async: false
  import ExUnit.CaptureLog
  import Mock

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
    Logger.configure(level: :info)

    {:ok, _pid} = Counter.start_link(0)

    on_exit(fn ->
      Logger.configure(level: old_log_level)
    end)

    :ok
  end

  describe "Retry" do
    test "automatically on Exception during event handling without GenServer restart" do
      start_supervised!(ExampleConsumer)

      capture_log([level: :warning], fn ->
        {:ok, _events} =
          JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 0})

        assert_receive :exception_during_event_handling, 500
        assert_receive :event_handled_successfully, 500
      end)
    end

    test "does not restart Listener process" do
      start_supervised!(ExampleConsumer)

      capture_log([level: :warning], fn ->
        listener_pid = Process.whereis(ExampleConsumer)

        {:ok, _events} =
          JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 0})

        assert_receive :event_handled_successfully, 500
        assert listener_pid == Process.whereis(ExampleConsumer)
      end)
    end

    test "stops EventStoreListener GenServer after 3 attempts" do
      start_supervised!(ExampleConsumer)

      logs =
        capture_log([level: :warning], fn ->
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

    test "allows to configure retry behaviour" do
      defmodule ExampleConsumerWithCustomConfig do
        use Shared.EventStoreListener,
          subscription_key: "example_consumer_with_custom_config",
          event_store: JehovakelEx.EventStore,
          retry_opts: [max_retries: 2, base_delay_in_ms: 8]

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

      start_supervised!(ExampleConsumerWithCustomConfig)

      logs =
        capture_log([level: :warning], fn ->
          listener_pid = Process.whereis(ExampleConsumerWithCustomConfig)

          {:ok, _events} =
            JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 3})

          assert_receive :exception_during_event_handling
          assert_receive :event_handled_successfully, 800

          assert listener_pid != Process.whereis(ExampleConsumerWithCustomConfig)
        end)

      assert logs =~ "ExampleConsumerWithCustomConfig is retrying (1/2)"
      assert logs =~ "ExampleConsumerWithCustomConfig is retrying (2/2)"
      assert logs =~ "is dying due to bad event after 2 retries"
    end

    test "allows to snooze on error" do
      defmodule SnoozingConsumer do
        use Shared.EventStoreListener,
          subscription_key: "snoozing_consumer",
          event_store: JehovakelEx.EventStore

        @impl true
        def handle(_event, _meta) do
          raise RuntimeError, "Please Snooze"
        end

        @impl true
        def on_error({:error, %RuntimeError{message: "Please Snooze"}}, _, _, _, _) do
          {:snooze, 37}
        end
      end

      start_supervised!(SnoozingConsumer)

      test_process = self()

      logs =
        capture_log(fn ->
          with_mock Process, [:passthrough],
            sleep: fn snooze_time -> send(test_process, {:snoozing, snooze_time}) end do
            {:ok, _events} = JehovakelEx.EventStore.append_event(@event, %{})
            assert_receive {:snoozing, 37}
          end
        end)

      assert logs =~ "Snoozing Shared.EventStoreListenerTest.SnoozingConsumer for 37ms"
    end
  end

  test "Log Stacktrace on failing to handle exception during event handling" do
    start_supervised!(ExampleConsumer)

    logs =
      capture_log([level: :warning], fn ->
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

  test "can configure custom restart option for the child spec" do
    defmodule TemporaryRestartConsumer do
      use Shared.EventStoreListener,
        subscription_key: "example_consumer",
        event_store: JehovakelEx.EventStore,
        restart: :temporary

      def handle(_event, %{}) do
        child_spec(:foo_bar_opts)
      end
    end

    assert TemporaryRestartConsumer.handle(@event, %{})[:restart] == :temporary
  end

  describe "__using__/1" do
    test "raises if subscription_key is missing" do
      assert_raise(RuntimeError, "subscription_key is required since v3.0", fn ->
        defmodule MissingSubscriptionKey do
          use Shared.EventStoreListener,
            event_store: JehovakelEx.EventStore
        end
      end)
    end

    test "raises if event_store is missing" do
      assert_raise(
        RuntimeError,
        "Event Store(event_store: My.EventStore) configuration is missing",
        fn ->
          defmodule MissingEventStore do
            use Shared.EventStoreListener,
              subscription_key: "example_consumer"
          end
        end
      )
    end
  end
end
