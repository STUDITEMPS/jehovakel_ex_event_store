---
name: implement-application-service
description: Implement a new application service following the established jobvalley patterns. Use when creating a new use case, command handler, or business operation that modifies state through the public API.
argument-hint: "[use-case-name]"
---

# Implement a New Application Service

Application services are the command handlers of the system. Every state-changing operation goes through an application service. The use case name (`$ARGUMENTS`) should be in German, snake_case.

## File Structure

```
lib/<app_name>/
  └── [domain]/
      └── [use_case]/
          └── [use_case]_application_service.ex
```

The application service typically lives inside the bounded context it belongs to, under a subdirectory named after the use case.

## Template

### Standard Application Service

```elixir
defmodule MyApp.MyUseCaseApplicationService do
  @moduledoc false
  use MyApp.Includes, :application_service

  alias MyApp.Events.MyEvent
  alias MyApp.MyEntity
  alias MyApp.MyEntityRepo

  def ausfuehren(entity_id: entity_id, some_value: value, metadata: metadata) do
    with {:ok, entity} <- MyEntityRepo.hole_my_entity(entity_id) do
      updated_entity = MyEntity.mit_some_field(entity, value)
      event = MyEvent.fuer(updated_entity)

      starte_transaction()
      |> persistiere_entity(updated_entity)
      |> persistiere_event(event, metadata)
      |> beende_transaction()
      |> return_result()
    end
  end

  defp persistiere_entity(multi, entity) do
    Multi.run(multi, :persistiere_entity, fn _, _ ->
      MyEntityRepo.persistiere_my_entity(entity)
    end)
  end

  defp persistiere_event(multi, event, metadata) do
    Multi.run(multi, :persistiere_event, fn _, _ ->
      metadata = event_metadata("my-use-case", metadata)
      append_event(event, metadata)
    end)
  end

  defp return_result({:ok, %{persistiere_entity: entity}}), do: {:ok, entity.id}
  defp return_result(result), do: super(result)
end
```

### Abrechnungsmodalitaeten Application Service

For billing modalities (Verrechnungssatz, Zahlungsziel, Rechnungsturnus, etc.), use the extended include which adds history tracking:

```elixir
defmodule MyApp.MyModalitaetFestlegenApplicationService do
  @moduledoc false
  use MyApp.Includes, :application_service_fuer_abrechnungsmodalitaeten

  alias MyApp.Events.MyModalitaetFestgelegt
  alias MyApp.MyModalitaet
  alias MyApp.MyModalitaetRepo

  def ausfuehren(auftragsnummer: auftragsnummer, value: value, gueltig_ab: gueltig_ab, metadata: metadata) do
    modalitaet =
      MyModalitaet.erfassen(
        auftragsnummer: auftragsnummer,
        value: value,
        gueltig_ab: gueltig_ab
      )

    event = MyModalitaetFestgelegt.fuer(modalitaet)

    starte_transaction()
    |> persistiere_modalitaet(modalitaet)
    |> persistiere_historie(erfassung_aufzeichnen_fuer(modalitaet, metadata))
    |> persistiere_event(event, metadata)
    |> beende_transaction()
    |> return_result()
  end

  defp persistiere_modalitaet(multi, modalitaet) do
    Multi.run(multi, :persistiere_modalitaet, fn _, _ ->
      MyModalitaetRepo.persistiere_my_modalitaet(modalitaet)
    end)
  end

  defp persistiere_event(multi, event, metadata) do
    Multi.run(multi, :persistiere_event, fn _, _ ->
      metadata = event_metadata("my-modalitaet-festlegen", metadata)
      append_event(event, metadata)
    end)
  end

  defp return_result({:ok, %{persistiere_modalitaet: modalitaet}}), do: {:ok, modalitaet.id}
  defp return_result(result), do: super(result)
end
```

## What the Includes Provide

### `:application_service`
- `import MyApp.EventStore, only: [append_event: 3, append_event: 2]`
- `import MyApp.Repo, only: [transaction: 1]`
- `import MyApp.Includes, only: [event_metadata: 2]`
- `alias Ecto.Multi`
- `require Logger`
- Helper functions: `starte_transaction/0`, `beende_transaction/1`, `return_result/1` (overridable), `return_either/1` (overridable, for `{:ok, value}` returns)

### `:application_service_fuer_abrechnungsmodalitaeten`
Everything from `:application_service` plus:
- `import MyApp.Abrechnungsmodalitaeten.HistorieAufzeichnen`
- Provides `persistiere_historie/2` and `erfassung_aufzeichnen_fuer/2` for audit trail

## Required Patterns

- Entry point is always `ausfuehren/1` accepting a keyword list
- Arguments use keyword syntax: `entity_id: id, value: v, metadata: metadata`
- `metadata` is always the last argument and must always be passed through
- Use `with` for preliminary validation (loading dependencies), then start transaction only on success
- Transaction steps are private functions wrapping `Multi.run/3`
- `event_metadata/2` takes a kebab-case command name string and the metadata keyword list
- Override `return_result/1` to extract specific values; call `super(result)` for the default clause
- The default `return_result/1` returns `:ok` on success, `{:error, reason}` on failure
- Use `return_either/1` instead when you need to return `{:ok, value}` (not just `:ok`)

## Registering in the Public API

Add a `definterface` call in `lib/<app_name>.ex`:

```elixir
definterface(:my_use_case,
  module: MyApp.MyUseCaseApplicationService,
  keyword_args: [:entity_id, :some_value, :metadata]
)
```

This generates `MyApp.my_use_case/1` delegating to `MyUseCaseApplicationService.ausfuehren/1`.

## Checklist

- [ ] Module name ends with `ApplicationService`
- [ ] Uses `use MyApp.Includes, :application_service` (or `_fuer_abrechnungsmodalitaeten`)
- [ ] `@moduledoc false`
- [ ] Entry point is `ausfuehren/1` with keyword list arguments
- [ ] `metadata` is the last keyword argument
- [ ] Transaction uses `starte_transaction() |> ... |> beende_transaction() |> return_result()`
- [ ] Each Multi step is a private function using `Multi.run/3`
- [ ] Event is created from domain entity and appended with `event_metadata/2` + `append_event/2`
- [ ] `return_result/1` is overridden with a clause matching `{:ok, %{step_key: value}}`
- [ ] Default `return_result/1` clause calls `super(result)`
- [ ] `definterface` added in `lib/<app_name>.ex`
- [ ] `mix format` passes
