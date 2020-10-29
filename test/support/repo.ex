defmodule Support.Repo do
  use Ecto.Repo,
    otp_app: :jehovakel_ex_event_store,
    adapter: Ecto.Adapters.Postgres
end
