import Config

config :jehovakel_ex_event_store,
  ecto_repos: [Support.Repo],
  event_stores: [JehovakelEx.EventStore]

# General Repository configuration
config :jehovakel_ex_event_store, Support.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: System.get_env("PG_USER") || "postgres",
  password: System.get_env("PG_PASSWORD") || "postgres",
  port: System.get_env("PG_PORT") || "5432",
  hostname: System.get_env("PG_HOST") || "postgres",
  database: System.get_env("PG_NAME") || "jehovakel_ex_#{config_env()}",
  # Avoid collisions with eventstore `schema_migrations` relation
  migration_source: "readstore_schema_migrations",
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  # erhöht die DB-Pool checkout timeouts, so dass die Tests mehr Zeit haben und durchlaufen können
  queue_target: 1_000,
  queue_interval: 5_000

config :jehovakel_ex_event_store, JehovakelEx.EventStore,
  serializer: EventStore.TermSerializer,
  username: System.get_env("PG_USER") || "postgres",
  password: System.get_env("PG_PASSWORD") || "postgres",
  port: System.get_env("PG_PORT") || "5432",
  hostname: System.get_env("PG_HOST") || "postgres",
  database: System.get_env("PG_NAME") || "jehovakel_ex_#{config_env()}",
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  # erhöht die DB-Pool checkout timeouts, so dass die Tests mehr Zeit haben und durchlaufen können
  queue_target: 1_000,
  queue_interval: 5_000

# TODO: set level :error, which breaks lib/event_store/event_store_listener_test.exs
config :logger, level: :error
