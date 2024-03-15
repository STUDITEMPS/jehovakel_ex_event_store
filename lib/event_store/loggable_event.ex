defprotocol Shared.LoggableEvent do
  @moduledoc """
  By implementing this protocol you can define how events will be logged by the EventStore.

  By default only the event name (the last segment of the module name) will be
  logged.

  ## Deriving

  If you don't want to change the format of the log message but only want to
  define the keys contained in the log message you can use the derive the
  protocol and provide the `:only` or the `:except` or :all option

      defmodule My.CustomEvent do
        @derive [{Shared.LoggableEvent, only: [:entity_id]}]
        defstruct [:entity_id, :data]
      end

      defmodule My.OtherEvent do
        @derive [{Shared.LoggableEvent, except: [:data]}]
        defstruct [:entity_id, :data]
      end

      defmodule My.UnconfidentialEvent do
        @derive [{Shared.LoggableEvent, :all}]
        defstruct [:entity_id, :data]
      end
  """

  @fallback_to_any true
  @doc "Converts an event to a loggable String"
  @spec to_log(struct) :: String.t()
  def to_log(event)
end

defimpl Shared.LoggableEvent, for: Any do
  defmacro __deriving__(module, _struct, options) do
    opts =
      case options do
        :all ->
          [except: []]

        [] ->
          []

        [except: keys] when is_list(keys) ->
          [except: keys]

        [only: keys] when is_list(keys) ->
          [only: keys]

        [except: _] ->
          raise CompileError,
            description: "Invalid option: :except must be a list",
            file: __CALLER__.file,
            line: __CALLER__.line

        [only: _] ->
          raise CompileError,
            description: "Invalid option: :only must be a list",
            file: __CALLER__.file,
            line: __CALLER__.line

        _ ->
          raise CompileError,
            description: "Options must be: :all | [only: list(atom)] | [except: list(atom)]",
            file: __CALLER__.file,
            line: __CALLER__.line
      end

    quote do
      defimpl Shared.LoggableEvent, for: unquote(module) do
        def to_log(arg) do
          unquote(__MODULE__).to_log(arg, unquote(opts))
        end
      end
    end
  end

  def to_log(event, opts \\ [])
  def to_log(%_{} = event, []), do: event_name(event)
  def to_log(%_{} = event, opts), do: "#{event_name(event)}: #{fields(event, opts)}"
  def to_log(_event, _), do: raise(ArgumentError, "Implement the Shared.LoggableEvent Protocol")

  defp fields(%_{} = event, opts) do
    event |> select_fields(opts) |> format_fields()
  end

  defp format_fields(fields) do
    Enum.map_join(fields, " ", fn {key, value} -> "#{key}=#{inspect(value)}" end)
  end

  defp select_fields(event, only: fields), do: Map.take(Map.from_struct(event), fields)
  defp select_fields(event, except: fields), do: Map.drop(Map.from_struct(event), fields)

  defp event_name(%event_type{}), do: List.last(Module.split(event_type))
end
