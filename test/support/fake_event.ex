# Because of consolidation the protocol implementation needs to live in a file
# that is compiled before the tests are executed. Check the "Consolidation"
# section in the documentation for Kernel.defprotocol/2

defmodule Shared.EventTest.FakeEvent do
  defstruct some: :default
end

defimpl Shared.LoggableEvent, for: Shared.EventTest.FakeEvent do
  def to_log(_event) do
    "FakeEvent: logging"
  end
end

defimpl Shared.AppendableEvent, for: Shared.EventTest.FakeEvent do
  def stream_id(event) do
    event.some |> Atom.to_string()
  end

  def streams_to_link(_event), do: []
end
