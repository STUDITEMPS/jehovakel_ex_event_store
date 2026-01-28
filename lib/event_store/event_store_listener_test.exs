defmodule Shared.EventStoreListenerTest do
  use Support.EventStoreCase, async: false

  import ExUnit.CaptureLog

  alias Shared.EventStoreListener.HandleMissingError
  alias Shared.EventTest.FakeEvent

  @event %FakeEvent{}

  defmodule EventHandlingError do
    @moduledoc false
    defexception [:message]
  end

  defmodule Counter do
    @moduledoc false
    use Agent

    def start_link(initial_value) do
      Agent.start_link(fn -> initial_value end, name: __MODULE__)
    end

    def increment do
      Agent.get_and_update(__MODULE__, &{&1, &1 + 1})
    end
  end

  defmodule ExampleListener do
    @moduledoc false
    use Shared.EventStoreListener,
      subscription_key: "example_listener",
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

  describe "Event Handling" do
    test "" do
      assert_raise HandleMissingError, fn ->
        defmodule IncompleteListener do
          @moduledoc false
          use Shared.EventStoreListener,
            subscription_key: "incomplete_listener",
            event_store: JehovakelEx.EventStore
        end
      end
    end

    test "EventListener can implement only handle/2" do
      defmodule Handle2Listener do
        @moduledoc false
        use Shared.EventStoreListener,
          subscription_key: "handle2_listener",
          event_store: JehovakelEx.EventStore

        def handle(_event, %{test_pid: test_pid}) do
          send(test_pid, :event_handled_successfully)
          :ok
        end
      end

      start_supervised!(Handle2Listener)

      JehovakelEx.EventStore.append_event(@event, %{test_pid: self()})
      assert_receive :event_handled_successfully
    end

    test "EventListener can implement only handle/3" do
      defmodule Handle3Listener do
        @moduledoc false
        use Shared.EventStoreListener,
          subscription_key: "handle3_listener",
          event_store: JehovakelEx.EventStore

        def handle(_event, %{test_pid: test_pid}, state) do
          send(test_pid, {:event_handled_successfully, state})
          :ok
        end
      end

      start_supervised!(Handle3Listener)

      JehovakelEx.EventStore.append_event(@event, %{test_pid: self()})
      assert_receive {:event_handled_successfully, _state}
    end

    test "EventListener add catch all fallback for handle/2" do
      defmodule Handle2FallbackListener do
        @moduledoc false
        use Shared.EventStoreListener,
          subscription_key: "handle2_fallback_listener",
          event_store: JehovakelEx.EventStore

        def handle(%FakeEvent{some: :default}, %{test_pid: test_pid}) do
          send(test_pid, :event_handled_successfully)
          :ok
        end
      end

      start_supervised!(Handle2FallbackListener)

      JehovakelEx.EventStore.append_event(%FakeEvent{some: :default}, %{test_pid: self()})
      assert_receive :event_handled_successfully
      JehovakelEx.EventStore.append_event(%FakeEvent{some: :custom_value}, %{test_pid: self()})
      refute_receive :event_handled_successfully
    end

    test "EventListener add catch all fallback for handle/3" do
      defmodule Handle3FallbackListener do
        @moduledoc false
        use Shared.EventStoreListener,
          subscription_key: "handle3_fallback_listener",
          event_store: JehovakelEx.EventStore

        def handle(%FakeEvent{some: :default}, %{test_pid: test_pid}, state) do
          send(test_pid, {:event_handled_successfully, state})
          :ok
        end
      end

      start_supervised!(Handle3FallbackListener)

      JehovakelEx.EventStore.append_event(%FakeEvent{some: :default}, %{test_pid: self()})
      assert_receive {:event_handled_successfully, _state}
      JehovakelEx.EventStore.append_event(%FakeEvent{some: :custom_value}, %{test_pid: self()})
      refute_receive {:event_handled_successfully, _state}
    end
  end

  describe "Retry" do
    test "automatically on Exception during event handling without GenServer restart" do
      start_supervised!(ExampleListener)

      capture_log([level: :warning], fn ->
        {:ok, _events} =
          JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 0})

        assert_receive :exception_during_event_handling, 500
        assert_receive :event_handled_successfully, 500
      end)
    end

    test "does not restart Listener process" do
      start_supervised!(ExampleListener)

      capture_log([level: :warning], fn ->
        listener_pid = Process.whereis(ExampleListener)

        {:ok, _events} =
          JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 0})

        assert_receive :event_handled_successfully, 500
        assert listener_pid == Process.whereis(ExampleListener)
      end)
    end

    test "stops EventStoreListener GenServer after 3 attempts" do
      start_supervised!(ExampleListener)

      logs =
        capture_log([level: :warning], fn ->
          listener_pid = Process.whereis(ExampleListener)

          {:ok, _events} =
            JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 3})

          assert_receive :exception_during_event_handling
          assert_receive :event_handled_successfully, 500

          assert listener_pid != Process.whereis(ExampleListener)
        end)

      assert logs =~ "ExampleListener is retrying (1/3)"
      assert logs =~ "ExampleListener is retrying (2/3)"
      assert logs =~ "ExampleListener is retrying (3/3)"
      assert logs =~ "is dying due to bad event after 3 retries"
    end

    test "allows to configure retry behaviour" do
      defmodule ExampleListenerWithCustomConfig do
        @moduledoc false
        use Shared.EventStoreListener,
          subscription_key: "example_listener_with_custom_config",
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

      start_supervised!(ExampleListenerWithCustomConfig)

      logs =
        capture_log([level: :warning], fn ->
          listener_pid = Process.whereis(ExampleListenerWithCustomConfig)

          {:ok, _events} =
            JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 3})

          assert_receive :exception_during_event_handling
          assert_receive :event_handled_successfully, 800

          assert listener_pid != Process.whereis(ExampleListenerWithCustomConfig)
        end)

      assert logs =~ "ExampleListenerWithCustomConfig is retrying (1/2)"
      assert logs =~ "ExampleListenerWithCustomConfig is retrying (2/2)"
      assert logs =~ "is dying due to bad event after 2 retries"
    end

    test "can shutdown during retry" do
      start_supervised!(ExampleListener)

      logs =
        capture_log([level: :warning], fn ->
          listener_pid = Process.whereis(ExampleListener)

          {:ok, _events} =
            JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 3})

          assert_receive :exception_during_event_handling
          assert_receive :exception_during_event_handling
          stop_supervised!(ExampleListener)

          refute_receive :exception_during_event_handling

          assert listener_pid != Process.whereis(ExampleListener)
        end)

      assert logs =~ "#{ExampleListener} failed"
      assert logs =~ "ExampleListener is retrying (1/3)"

      refute logs =~ "ExampleListener is retrying (2/3)"
      refute logs =~ "is dying due to bad event after 3 retries"
    end

    test "allows to snooze on error" do
      test_process = self()

      defmodule SnoozingListener do
        @moduledoc false
        use Shared.EventStoreListener,
          subscription_key: "snoozing_listener",
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

      {:ok, state} =
        Shared.EventStoreListener.init(%{
          name: SnoozingListener,
          handler_module: SnoozingListener,
          event_store: JehovakelEx.EventStore,
          subscription_key: "snoozing_listener",
          subscription: nil,
          start_from: :origin,
          retry_opts: [max_retries: 3, base_delay_in_ms: 10]
        })

      assert_receive {:subscribed, _}

      {:ok, _events} = JehovakelEx.EventStore.append_event(@event, %{})

      assert_receive {:events, events}

      logs =
        capture_log(fn ->
          assert {:noreply, _state} =
                   Shared.EventStoreListener.handle_info({:events, events}, state)
        end)

      refute_received {:events, ^events}
      assert_receive {:events, ^events}

      assert logs =~ "Snoozing Shared.EventStoreListenerTest.SnoozingListener for 37ms"
    end
  end

  test "does graceful shutdown when GenServer is stopped" do
    defmodule SlowListener do
      @moduledoc false
      use Shared.EventStoreListener,
        subscription_key: "slow_listener",
        event_store: JehovakelEx.EventStore

      def handle(_event, meta) do
        send(meta.test_pid, :event_handling_started)
        Process.sleep(100)
        send(meta.test_pid, :event_handling_done)
        :ok
      end
    end

    start_supervised!(SlowListener)
    {:ok, _events} = JehovakelEx.EventStore.append_event(@event, %{test_pid: self()})

    assert_receive :event_handling_started
    stop_supervised!(SlowListener)
    # we only receive this if the event listener is not killed immediately
    assert_receive :event_handling_done
  end

  test "ignores normal exits" do
    {:ok, pid} = ExampleListener.start_link([])

    spawn(fn -> Process.exit(pid, :normal) end)

    {:ok, _events} = JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 0})
    assert_receive :event_handled_successfully
  end

  test "stops on abnormal exits of non parent process" do
    {:ok, pid} = ExampleListener.start_link([])
    Process.unlink(pid)
    Process.monitor(pid)

    # The Genserver handles exits from the parent process automatically with calling terminate/2
    spawn(fn -> Process.exit(pid, :halt_stop) end)

    {:ok, _events} = JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 0})
    refute_receive :event_handled_successfully
    assert_receive {:DOWN, _ref, :process, ^pid, :halt_stop}
  end

  test "accepts Timex.Duration as :snooze delay" do
    defmodule SnoozingDurationListener do
      @moduledoc false
      use Shared.EventStoreListener,
        subscription_key: "snoozing_listener",
        event_store: JehovakelEx.EventStore

      @impl true
      def handle(_event, _meta) do
        raise RuntimeError, "Please Snooze"
      end

      @impl true
      def on_error({:error, %RuntimeError{message: "Please Snooze"}}, _, _, _, _) do
        {:snooze, Timex.Duration.from_milliseconds(30)}
      end
    end

    {:ok, state} =
      Shared.EventStoreListener.init(%{
        name: SnoozingDurationListener,
        handler_module: SnoozingDurationListener,
        event_store: JehovakelEx.EventStore,
        subscription_key: "snoozing_duration_listener",
        subscription: nil,
        start_from: :origin,
        retry_opts: [max_retries: 3, base_delay_in_ms: 10]
      })

    assert_receive {:subscribed, _}

    {:ok, _events} = JehovakelEx.EventStore.append_event(@event, %{})
    assert_receive {:events, events}

    logs =
      capture_log(fn ->
        assert {:noreply, _state} =
                 Shared.EventStoreListener.handle_info({:events, events}, state)
      end)

    refute_received {:events, ^events}
    assert_receive {:events, ^events}

    assert logs =~ "Snoozing Shared.EventStoreListenerTest.SnoozingDurationListener for PT0.03S"
  end

  test "Log Stacktrace on failing to handle exception during event handling" do
    start_supervised!(ExampleListener)

    logs =
      capture_log([level: :warning], fn ->
        {:ok, _events} =
          JehovakelEx.EventStore.append_event(@event, %{test_pid: self(), raise_until: 4})

        assert_receive :exception_during_event_handling
        assert_receive :event_handled_successfully, 500
      end)

    assert logs =~ "Stacktrace"
    assert logs =~ "BAM BAM BAM"
    assert logs =~ "Shared.EventStoreListenerTest.ExampleListener"
    assert logs =~ "lib/event_store/event_store_listener_test.exs"
  end

  test "can configure custom restart option for the child spec" do
    defmodule TemporaryRestartListener do
      @moduledoc false
      use Shared.EventStoreListener,
        subscription_key: "example_listener",
        event_store: JehovakelEx.EventStore,
        restart: :temporary

      def handle(_event, %{}) do
        child_spec(:foo_bar_opts)
      end
    end

    assert TemporaryRestartListener.handle(@event, %{})[:restart] == :temporary
  end

  describe "__using__/1" do
    test "raises if subscription_key is missing" do
      assert_raise(RuntimeError, "subscription_key is required since v3.0", fn ->
        defmodule MissingSubscriptionKey do
          @moduledoc false
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
            @moduledoc false
            use Shared.EventStoreListener,
              subscription_key: "example_listener"
          end
        end
      )
    end
  end
end
