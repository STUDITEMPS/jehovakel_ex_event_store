defprotocol Shared.AppendableEvent do
  @doc "Returns the stream ID to which the event could be appended."
  def stream_id(event)

  @doc "Returns the list of fields to link the event to fields values inside the event"
  def streams_to_link(event)
end

defimpl Shared.AppendableEvent, for: Any do
  defmacro __deriving__(module, _struct, options) do
    quote do
      defimpl Shared.AppendableEvent, for: unquote(module) do
        def stream_id(event) do
          stream_id_field = Keyword.fetch!(unquote(options), :stream_id)
          stream_id = Map.fetch!(event, stream_id_field)

          unless is_binary(stream_id) do
            raise ArgumentError, "Stream ID has to be a string, got '#{inspect(stream_id)}'."
          end

          stream_id
        end

        def streams_to_link(event) do
          fields_to_link = Keyword.get(unquote(options), :streams_to_link, []) |> List.wrap()

          invalid_links =
            Enum.reduce(fields_to_link, %{}, fn field, errors ->
              field_value = Map.get(event, field)

              if is_binary(field_value) do
                errors
              else
                Map.put(errors, field, field_value)
              end
            end)

          if map_size(invalid_links) > 0 do
            invalid_links =
              Enum.map_join(
                invalid_links,
                ", ",
                fn {field, value} ->
                  "#{field} -> #{inspect(value)}"
                end
              )

            raise ArgumentError,
                  "Streams ids to link need to be a string, got '#{invalid_links}'."
          end

          Map.take(event, fields_to_link) |> Map.values()
        end
      end
    end
  end

  # No default available
  def stream_id(_event), do: raise(ArgumentError, "Implement the Appendable Protocol")

  def streams_to_link(_event), do: []
end
