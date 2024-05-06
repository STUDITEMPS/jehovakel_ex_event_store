# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
import Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :jehovakel_ex_event_store, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:jehovakel_ex_event_store, :key)
#
# You can also configure a 3rd-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#

config :jehovakel_ex_event_store,
  ecto_repos: [Support.JehovakelExRepo]

# General Repository configuration
config :jehovakel_ex_event_store, Support.JehovakelExRepo,
  username: System.get_env("PG_USER") || "postgres",
  password: System.get_env("PG_PASSWORD") || "postgres",
  port: System.get_env("PG_PORT") || "5432",
  hostname: System.get_env("PG_HOST") || "postgres",
  database: System.get_env("PG_NAME") || "jehovakel_ex_event_store_#{config_env()}",
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  migration_source: "readstore_schema_migrations"

config :eventstore, EventStore.Storage,
  serializer: EventStore.TermSerializer,
  username: System.get_env("PG_USER") || "postgres",
  password: System.get_env("PG_PASSWORD") || "postgres",
  port: System.get_env("PG_PORT") || "5432",
  hostname: System.get_env("PG_HOST") || "postgres",
  database: System.get_env("PG_NAME") || "jehovakel_ex_event_store_#{config_env()}",
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

import_config "#{config_env()}.exs"
