if Code.ensure_loaded?(Ecto) && Code.ensure_loaded?(Shared.Ecto.Term) do
  defmodule Shared.EventStore.Migration.Event do
    @moduledoc """
    Warnung: Diese Datei ist ungetestet. Vergewissere dich, dass du deine Skripte, die darauf basieren gut lokal und
    auf Staging getestet sind, bevor du diese auf Production loslässt!!!
    """
    use Ecto.Schema
    import Ecto.Query
    import Ecto.Changeset
    require Logger

    @primary_key {:event_id, :binary_id, autogenerate: false}
    schema "events" do
      field(:event_type, :string)
      field(:data, Shared.Ecto.Term)
      field(:metadata, Shared.Ecto.Term)
      field(:created_at, :utc_datetime)
      field(:causation_id, :binary_id)
      field(:correlation_id, :binary_id)
    end

    def migrate_event(event_type_to_migrate, migration, repository)
        when is_atom(event_type_to_migrate) and is_function(migration) do
      event_type = Atom.to_string(event_type_to_migrate)

      query =
        from(
          e in Shared.EventStore.Migration.Event,
          where: e.event_type == ^event_type
        )

      anzahl_events = repository.aggregate(query, :count)

      events = repository.stream(query)

      if anzahl_events > 0 do
        Logger.info(
          "Migrating " <>
            to_string(anzahl_events) <> " Events vom Typ " <> to_string(event_type_to_migrate)
        )

        Ecto.Adapters.SQL.query!(
          repository,
          "ALTER TABLE events DISABLE TRIGGER no_update_events"
        )

        Ecto.Adapters.SQL.query!(
          repository,
          "ALTER TABLE events DISABLE TRIGGER no_delete_events"
        )

        repository.transaction(
          fn ->
            Enum.each(events, fn event ->
              case run_migration(migration, event) do
                {new_data, new_metadata} ->
                  %event_module{} = new_data
                  event_type = Atom.to_string(event_module)

                  {:ok, migrated_at} = DateTime.now("Europe/Berlin")

                  new_metadata =
                    new_metadata
                    |> Enum.into(%{})
                    |> Map.merge(%{migrated_at: migrated_at, original_event: event.data})

                  changeset =
                    change(event, event_type: event_type, data: new_data, metadata: new_metadata)

                  repository.update!(changeset)

                :skip ->
                  Logger.info("Skipping event #{event.event_id}")

                other ->
                  Logger.warn("Return value of '#{inspect(other)}' is not supported.")
              end
            end)
          end,
          timeout: 600_000_000
        )
      end
    after
      Ecto.Adapters.SQL.query!(repository, "ALTER TABLE events ENABLE TRIGGER no_delete_events")
      Ecto.Adapters.SQL.query!(repository, "ALTER TABLE events ENABLE TRIGGER no_update_events")
    end

    defp run_migration(migration, event) when is_function(migration, 2) do
      migration.(event.data, event.metadata)
    end

    defp run_migration(migration, event) when is_function(migration, 3) do
      migration.(event.data, event.metadata, %{
        id: event.event_id,
        type: event.event_type,
        created_at: event.created_at,
        causation_id: event.causation_id,
        correlation_id: event.correlation_id
      })
    end
  end
end
