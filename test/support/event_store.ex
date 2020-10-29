defmodule JehovakelEx.EventStore do
  use EventStore, otp_app: :jehovakel_ex_event_store
  use Shared.EventStore
end
