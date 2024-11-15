defmodule Shared.MixProject do
  use Mix.Project

  def project do
    [
      app: :jehovakel_ex_event_store,
      version: "3.0.1",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      test_paths: ["lib"],
      test_coverage: [tool: ExCoveralls],
      deps: deps(),
      aliases: aliases(),
      consolidate_protocols: Mix.env() != :test,
      name: "Jehovakel EX EventStore",
      source_url: "https://github.com/STUDITEMPS/jehovakel_ex_event_store",
      description: description(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      test: ["ecto.create --quiet", "event_store.init", "ecto.migrate", "test"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # CQRS event store using PostgreSQL for persistence
      {:eventstore, ">= 1.2.1"},
      {:ecto, "~> 3.0", optional: true},
      {:ecto_sql, "~> 3.0", optional: true},
      {:timex, "~> 3.7", optional: true},
      {:mock, "~> 0.3.0", only: :test, optional: true},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false, optional: true},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false, optional: true}
    ]
  end

  defp description do
    "Thin wrapper around the Elixir EventStore providing a convenient interface."
  end

  defp package do
    [
      # This option is only needed when you don't want to use the OTP application name
      name: "jehovakel_ex_event_store",
      # These are the default files included in the package
      licenses: ["MIT License"],
      links: %{
        "GitHub" => "https://github.com/STUDITEMPS/jehovakel_ex_event_store",
        "Studitemps" => "https://tech.studitemps.de"
      }
    ]
  end
end
