defprotocol Shared.LoggableEvent do
  @doc "Converts an event to a loggable String"
  @fallback_to_any true
  def to_log(event)
end

defimpl Shared.LoggableEvent, for: Any do
  def to_log(%event_type{} = event) do
    event_type = event_type |> Atom.to_string() |> String.split(".") |> Enum.at(-1)

    event_data =
      event
      |> Map.from_struct()
      |> Enum.reduce("", fn {key, value}, event_as_string ->
        event_as_string <> " #{key}=" <> inspect(value)
      end)

    ~s(#{event_type}:#{event_data})
  end

  def to_log(_event), do: raise(ArgumentError, "Implement the Shared.LoggableEvent Protocol")
end
