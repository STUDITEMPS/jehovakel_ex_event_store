defmodule Shared.EventStoreListener do
  use GenServer
  require Logger
  alias EventStore.RecordedEvent

  defmodule ErrorContext do
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

    def delay(%__MODULE__{
          error_count: error_count,
          max_retries: max_retries,
          base_delay_in_ms: base_delay_in_ms
        })
        when error_count <= max_retries do
      # Exponential backoff
      sleep_duration = (:math.pow(2, error_count) * base_delay_in_ms) |> round()

      Process.sleep(sleep_duration)
    end
  end

  @type domain_event :: struct()
  @type metadata :: map()
  @type error_context :: ErrorContext.t()
  @type state :: map() | list()
  @type handle_result :: :ok | {:error, reason :: any()}

  @callback handle(domain_event(), metadata()) :: handle_result()
  @callback handle(domain_event(), metadata(), state()) :: handle_result()
  @callback on_error(
              error :: term(),
              failed_event :: domain_event(),
              metadata :: metadata(),
              error_context :: error_context()
            ) ::
              {:retry, error_context :: error_context()}
              | {:retry, delay :: non_neg_integer(), error_context :: error_context()}
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
              | {:retry, delay :: non_neg_integer(), error_context :: error_context()}
              | :skip
              | {:stop, reason :: term()}

  defmacro __using__(opts) do
    opts = opts || []

    quote location: :keep do
      @opts unquote(opts) || []
      Shared.EventStoreListener.validate_using_options(@opts)

      @name @opts[:name] || __MODULE__

      @behaviour Shared.EventStoreListener

      # Adds default handle method
      @before_compile unquote(__MODULE__)

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
    end
  end

  def start_link(name, handler_module, opts) do
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

  defmacro __before_compile__(_env) do
    quote generated: true do
      def init(state) do
        {:ok, state}
      end

      defoverridable init: 1

      def handle(_event, _metadata), do: :ok
      defoverridable handle: 2

      def handle(event, metadata, _state), do: handle(event, metadata)
      defoverridable handle: 3

      def on_error({:error, reason}, _event, _metadata, error_context),
        do: {:retry, error_context}

      defoverridable on_error: 4

      def on_error(error, _stacktrace, event, metadata, error_context),
        do: on_error(error, event, metadata, error_context)

      defoverridable on_error: 5
    end
  end

  @impl true
  def init(%{handler_module: handler_module, event_store: event_store} = state) do
    with {:ok, new_state} <- handler_module.init(state),
         subscription_key = new_state[:subscription_key],
         start_from = new_state[:start_from] || :origin,
         {:ok, subscription} <-
           event_store.subscribe_to_all_streams(
             subscription_key,
             self(),
             start_from: start_from
           ) do
      {:ok, %{new_state | subscription: subscription}}
    end
  end

  @impl true
  def handle_info({:subscribed, _subscription}, %{name: name} = state) do
    Logger.debug(fn ->
      "#{name} sucessfully subscribed to event store."
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:events, events}, %{name: name, retry_opts: retry_opts} = state) do
    Logger.debug(fn -> "#{name} received events: #{inspect(events)}" end)

    try do
      Enum.each(events, fn event -> handle_event(event, state, ErrorContext.new(retry_opts)) end)
      {:noreply, state}
    catch
      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  defp handle_event(
         %RecordedEvent{} = event,
         %{name: name} = state,
         %ErrorContext{} = error_context
       ) do
    case delegate_event_to_handler(event, state) do
      :ok ->
        ack_event(event, state)

      {:ok, _} ->
        ack_event(event, state)

      {:error, reason} ->
        Logger.error(fn ->
          "#{name} failed to handle event #{inspect(event)} due to #{inspect(reason)}"
        end)

        handle_error({:error, reason}, current_stacktrace(), event, state, error_context)

      {:error, reason, stacktrace} ->
        Logger.error(fn ->
          "#{name} failed to handle event #{inspect(event)} due to #{inspect(reason)}"
        end)

        handle_error({:error, reason}, stacktrace, event, state, error_context)
    end
  end

  defp delegate_event_to_handler(
         %RecordedEvent{} = event,
         %{
           handler_module: handler_module
         } = state
       ) do
    try do
      {domain_event, metadata} = Shared.EventStoreEvent.unwrap(event)
      handler_module.handle(domain_event, metadata, state)
    rescue
      error ->
        {:error, error, __STACKTRACE__}
    end
  end

  defp handle_error(
         error,
         stacktrace,
         event,
         %{handler_module: handler_module, name: name} = state,
         context
       ) do
    %RecordedEvent{data: domain_event, metadata: metadata} = event

    case handler_module.on_error(error, stacktrace, domain_event, metadata, context) do
      {:retry, %ErrorContext{} = context} ->
        context = ErrorContext.record_error(context)

        if ErrorContext.retry?(context) do
          ErrorContext.delay(context)

          Logger.warn(fn ->
            "#{name} is retrying (#{context.error_count}/#{context.max_retries}) failed event #{inspect(event)}"
          end)

          handle_event(event, state, context)
        else
          reason =
            "#{name} is dying due to bad event after #{ErrorContext.retry_count(context)} retries #{inspect(error)}, Stacktrace: #{inspect(stacktrace)}"

          Logger.warn(reason)

          throw({:error, reason})
        end

      :skip ->
        Logger.debug(fn ->
          "#{name} is skipping event #{inspect(event)}"
        end)

        ack_event(event, state)

      {:stop, reason} ->
        reason = "#{name} has requested to stop in on_error/5 callback with #{inspect(reason)}"

        Logger.warn(reason)
        throw({:error, reason})

      error ->
        Logger.warn(fn ->
          "#{name} on_error/5 returned an invalid response #{inspect(error)}"
        end)

        throw(error)
    end
  end

  defp current_stacktrace do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stacktrace} -> stacktrace
      nil -> "Process is not alive. No stacktrace available"
    end
  end

  defp ack_event(event, %{subscription: subscription, event_store: event_store}) do
    :ok = event_store.ack(subscription, event)
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
end
