defmodule Shared.EventStoreListener do
  @moduledoc false
  use GenServer

  alias EventStore.RecordedEvent

  require Logger

  defmodule ErrorContext do
    @moduledoc false
    defstruct [:error_count, :max_retries, :base_delay_in_ms]

    @type t :: %__MODULE__{
            error_count: integer,
            max_retries: integer,
            base_delay_in_ms: integer
          }

    def new(max_retries: max_retries, base_delay_in_ms: base_delay_in_ms) do
      %__MODULE__{error_count: 0, max_retries: max_retries, base_delay_in_ms: base_delay_in_ms}
    end

    def record_error(%__MODULE__{} = context) do
      Map.update(context, :error_count, 1, fn error_count -> error_count + 1 end)
    end

    def retry?(%__MODULE__{error_count: error_count, max_retries: max_retries}) do
      error_count <= max_retries
    end

    def retry_count(%__MODULE__{error_count: error_count}) do
      error_count - 1
    end

    def delay(%__MODULE__{error_count: error_count, max_retries: max_retries, base_delay_in_ms: base_delay_in_ms})
        when error_count <= max_retries do
      # Exponential backoff
      round(:math.pow(2, error_count) * base_delay_in_ms)
    end
  end

  @type domain_event :: struct()
  @type metadata :: map()
  @type error_context :: ErrorContext.t()
  @type state :: map() | list()
  @type handle_result :: :ok | {:error, reason :: any()}

  if Code.ensure_loaded?(Kernel) and function_exported?(Kernel, :to_timeout, 1) do
    @type unit :: :week | :day | :hour | :minute | :second | :millisecond
    @type delay ::
            non_neg_integer() | [{unit(), non_neg_integer()}] | Duration.t() | Timex.Duration.t()
  else
    @type delay :: non_neg_integer() | Timex.Duration.t()
  end

  @callback handle(domain_event(), metadata()) :: handle_result()
  @callback handle(domain_event(), metadata(), state()) :: handle_result()
  @callback on_error(
              error :: term(),
              failed_event :: domain_event(),
              metadata :: metadata(),
              error_context :: error_context()
            ) ::
              {:retry, error_context :: error_context()}
              | {:snooze, delay()}
              | :skip
              | {:stop, reason :: term()}

  @callback on_error(
              error :: term(),
              stacktrace :: list(),
              failed_event :: domain_event(),
              metadata :: metadata(),
              error_context :: error_context()
            ) ::
              {:retry, error_context :: error_context()}
              | {:snooze, delay()}
              | :skip
              | {:stop, reason :: term()}

  @callback terminate(reason :: term(), state :: term()) :: term()

  @optional_callbacks terminate: 2

  defmacro __using__(opts) do
    opts = opts || []

    Shared.EventStoreListener.validate_using_options(opts)

    quote location: :keep do
      @opts unquote(opts) || []
      @name @opts[:name] || __MODULE__

      @behaviour Shared.EventStoreListener

      def start_link(opts \\ []) do
        opts = Keyword.merge(@opts, opts)
        Shared.EventStoreListener.start_link(@name, __MODULE__, opts)
      end

      def child_spec(opts) do
        default = %{
          id: @name,
          start: {__MODULE__, :start_link, [opts]},
          restart: @opts[:restart] || :permanent,
          type: :worker
        }

        Supervisor.child_spec(default, [])
      end

      def init(state), do: {:ok, state}
      defoverridable init: 1

      def handle(_event, _metadata), do: :ok
      defoverridable handle: 2

      def handle(event, metadata, _state), do: handle(event, metadata)
      defoverridable handle: 3

      def on_error({:error, reason}, _event, _metadata, error_context), do: {:retry, error_context}

      defoverridable on_error: 4

      def on_error(error, _stacktrace, event, metadata, error_context),
        do: on_error(error, event, metadata, error_context)

      defoverridable on_error: 5
    end
  end

  def start_link(name, handler_module, opts) do
    Code.ensure_loaded!(handler_module)

    default_opts = %{
      name: nil,
      handler_module: nil,
      subscription: nil,
      start_from: :origin,
      retry_opts: [max_retries: 3, base_delay_in_ms: 10]
    }

    opts = Enum.into(opts, default_opts)
    state = %{opts | handler_module: handler_module, name: name}

    GenServer.start_link(__MODULE__, state, name: name)
  end

  @impl true
  def init(%{handler_module: handler_module} = state) do
    Process.flag(:trap_exit, true)

    with {:ok, new_state} <- handler_module.init(state),
         {:ok, new_state} <- subscribe(new_state) do
      {:ok, Map.put(new_state, :error_context, nil)}
    end
  end

  @impl true
  def handle_info({:subscribed, _subscription}, %{name: name} = state) do
    Logger.debug("#{name} sucessfully subscribed to event store.")

    {:noreply, state}
  end

  # We expect that we only ever receive 1 event at a time (see `subscribe/1`).
  # Also we expect that we only ever have 1 {:events, [event]} in the message queue.
  # Otherwise the retry mechanism will not keep the the events in order.
  @impl true
  def handle_info({:events, [event]}, %{name: name, error_context: nil} = state) do
    Logger.debug("#{name} received event: #{inspect(event)}")
    handle_event(event, state, ErrorContext.new(state.retry_opts))
  end

  def handle_info({:events, [event]}, %{name: name, error_context: context} = state) do
    Logger.warning("#{name} is retrying (#{context.error_count}/#{context.max_retries}) failed event #{inspect(event)}")

    handle_event(event, state, context)
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def terminate(reason, %{handler_module: handler_module} = state) do
    state = unsubscribe(state)

    if function_exported?(handler_module, :terminate, 2),
      do: handler_module.terminate(reason, state)
  end

  defp handle_event(%RecordedEvent{} = event, %{handler_module: handler_module} = state, %ErrorContext{} = error_context) do
    {domain_event, metadata} = Shared.EventStoreEvent.unwrap(event)
    handler_module.handle(domain_event, metadata, state)
  rescue
    error -> handle_error({:error, error}, __STACKTRACE__, event, state, error_context)
  catch
    {:error, reason} -> {:stop, reason, state}
  else
    :ok -> {:noreply, ack_event(event, state)}
    {:ok, _} -> {:noreply, ack_event(event, state)}
    {:error, _} = error -> handle_error(error, current_stacktrace(), event, state, error_context)
  end

  defp handle_error(
         {:error, reason} = error,
         stacktrace,
         %RecordedEvent{data: domain_event, metadata: metadata} = event,
         %{handler_module: handler_module, name: name} = state,
         context
       ) do
    Logger.error("#{name} failed to handle event #{inspect(event)} due to #{inspect(reason)}")

    case handler_module.on_error(error, stacktrace, domain_event, metadata, context) do
      {:snooze, delay} ->
        handle_snooze(event, delay, error, stacktrace, state)

      {:retry, %ErrorContext{} = context} ->
        handle_retry(event, ErrorContext.record_error(context), error, stacktrace, state)

      :skip ->
        Logger.debug("#{name} is skipping event #{inspect(event)}")
        {:noreply, ack_event(event, state)}

      {:stop, reason} ->
        reason = "#{name} has requested to stop in on_error/5 callback with #{inspect(reason)}"
        Logger.warning(reason)
        {:stop, reason, state}

      error ->
        Logger.warning("#{name} on_error/5 returned an invalid response #{inspect(error)}")

        throw(error)
    end
  end

  defp handle_retry(event, context, error, stacktrace, state) do
    if ErrorContext.retry?(context) do
      Process.send_after(self(), {:events, [event]}, ErrorContext.delay(context))

      {:noreply, %{state | error_context: context}}
    else
      reason =
        "#{state.name} is dying due to bad event after #{ErrorContext.retry_count(context)} retries #{format_error(error)}. Stacktrace: #{inspect(stacktrace)}"

      Logger.warning(reason)
      {:stop, reason, state}
    end
  end

  defp handle_snooze(event, delay, error, stacktrace, state) do
    {delay, delay_string} = unify_delay(delay)

    Logger.info(
      "Snoozing #{inspect(state.name)} for #{delay_string} while processing event #{inspect(event)}. Reason: #{format_error(error, stacktrace)}"
    )

    Process.send_after(self(), {:events, [event]}, delay)
    {:noreply, state}
  end

  defp current_stacktrace do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stacktrace} -> stacktrace
      nil -> "Process is not alive. No stacktrace available"
    end
  end

  defp subscribe(state) do
    subscription_key = state[:subscription_key]
    start_from = state[:start_from] || :origin
    event_store = state.event_store

    with {:ok, subscription} <-
           event_store.subscribe_to_all_streams(
             subscription_key,
             self(),
             start_from: start_from,
             # Explicitly set buffer size to 1 to ensure sequential processing.
             buffer_size: 1
           ) do
      {:ok, %{state | subscription: subscription}}
    end
  end

  defp unsubscribe(state) do
    subscription_key = state[:subscription_key]
    event_store = state.event_store

    with :ok <- event_store.unsubscribe_from_all_streams(subscription_key) do
      {:ok, %{state | subscription: nil}}
    end
  end

  defp ack_event(event, %{subscription: subscription, event_store: event_store} = state) do
    :ok = event_store.ack(subscription, event)
    %{state | error_context: nil}
  end

  def validate_using_options(opts) do
    valid_event_store?(opts[:event_store]) ||
      raise "Event Store(event_store: My.EventStore) configuration is missing"

    valid_subscription_key?(opts[:subscription_key]) ||
      raise "subscription_key is required since v3.0"
  end

  defp valid_event_store?(nil), do: false
  defp valid_event_store?(_), do: true

  defp valid_subscription_key?(key) when is_binary(key) do
    key != ""
  end

  defp valid_subscription_key?(_), do: false

  # Wir verwenden diese Schreibweisen um die Dependency auf Timex optional zu halten.
  defp unify_delay(%{__struct__: Timex.Duration} = delay) do
    {apply(Timex.Duration, :to_milliseconds, [delay, [truncate: true]]), apply(Timex.Duration, :to_string, [delay])}
  end

  if function_exported?(Kernel, :to_timeout, 1) do
    defp unify_delay(delay) when is_list(delay) when is_integer(delay) when is_struct(delay, Duration) do
      t = to_timeout(delay)
      {t, "#{t}ms"}
    end
  else
    defp unify_delay(delay) when is_integer(delay) and delay >= 0 do
      {delay, "#{delay}ms"}
    end
  end

  defp format_error(error, stacktrace \\ [])

  defp format_error({:error, reason}, stacktrace) when is_exception(reason),
    do: Exception.format(:error, reason, stacktrace)

  defp format_error({:error, reason}, _stacktrace), do: inspect(reason)
  defp format_error(error, _stacktrace), do: inspect(error)
end
