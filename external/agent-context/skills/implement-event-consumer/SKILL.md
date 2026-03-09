---
name: implement-event-consumer
description: Implement a new event consumer to handle incoming domain events from other bounded contexts over RabbitMQ. Use when integrating with a new external event, adding a new consumer for an existing event type, or connecting to a new remote exchange.
argument-hint: "[event-name]"
---

# Implement a New Event Consumer

Event consumers handle incoming domain events from other bounded contexts over RabbitMQ. The event name (`$ARGUMENTS`) should match the routing key format (e.g., `auftragserstellung.auftrag-erstellt`).

## File Structure

```
lib/[context]/
  └── [event_name]_event_consumer.ex
```

Consumer files typically live under a directory named after the **remote bounded context** (e.g., `lib/auftragserstellung/`, `lib/freigabe/`). Some consumers that handle internal events may live under `lib/<app_name>/` subdirectories.

## Template

```elixir
defmodule RemoteContext.MyEventConsumer do
  @moduledoc false
  use MyApp.EventConsumer,
    routing_key: "remote-context.event-name",
    remote_exchange: "remote-context"

  def handle(event, handler \\ &MyApp.my_application_service/1) do
    case event
         |> map_attributes()
         |> handler.()
         |> successful_if(:already_persisted) do
      :ok -> :ok
      error -> throw({:retry, error})
    end
  end

  defp map_attributes(
         %{
           "@type" => [
             "https://studitemps.tech/specification/remote-context/event-name",
             "https://studitemps.tech/specification/domain-event"
           ],
           "event_payload_key" => %{
             "@id" => entity_id,
             "some_field" => some_value
           }
         } = event
       ) do
    [
      entity_id: entity_id,
      some_value: some_value,
      metadata: extract_event_metadata(event)
    ]
  end
end
```

## What `use MyApp.EventConsumer` Provides

- Wraps `Tackle.Consumer` with standardized defaults (`retry_limit: 10`, `retry_delay: 10`)
- `handle_message/1` — deserializes JSON and delegates to your `handle/1`
- `extract_event_metadata/1` — extracts standard metadata fields from the event:
  ```elixir
  %{
    causation_id: event["@id"],
    original_causation_id: event["caused_by"],
    correlation_id: event["correlates_with"] || event["@id"],
    enacted_by: event["enacted_by"],
    occurred_at: parse_time(event["occurred_at"]),
    received_at: Timex.local()
  }
  ```
- `parse_interval/1` — parses ISO8601 interval strings into `[startzeit: datetime, endzeit: datetime]`
- `parse_time/1` (private) — parses ISO8601 datetime strings
- `on_error/5` — reports final failures to error tracking (Rollbar)
- `import Shared.CodeFlow, only: [successful_if: 2]` — treats specific error atoms as success

## Required Patterns

- `use MyApp.EventConsumer` with `routing_key` and `remote_exchange` options
- `@moduledoc false`
- `handle/2` with a default handler function parameter
  - The handler defaults to the public API function (e.g., `\\ &MyApp.my_service/1`)
  - Some consumers store the handler in a module attribute (`@handler` or `@application_service_handler_fn`), others use inline defaults — both are acceptable
  - Making it a parameter enables testing with mock handlers
- `map_attributes/1` pattern-matches on the `@type` array to identify the event
  - Always match the full `@type` list for safety
  - Always call `extract_event_metadata(event)` and include it as `:metadata` in the result
- Error handling:
  - Return `:ok` on success
  - Use `successful_if(:already_persisted)` to treat idempotent duplicates as success
  - `throw({:retry, error})` for transient/retriable failures
- Custom `retry_delay` can be set in the `use` options (default: 10 seconds)

## Event Structure Reference

All incoming events follow this structure:

```json
{
  "@type": [
    "https://studitemps.tech/specification/CONTEXT/EVENT-NAME",
    "https://studitemps.tech/specification/domain-event"
  ],
  "@id": "tech.studitemps:context:event-name:uuid",
  "caused_by": "tech.studitemps:...:uuid",
  "correlates_with": "tech.studitemps:...:uuid",
  "enacted_by": "tech.studitemps:identity:studitempsmitarbeiter:email",
  "occurred_at": "2024-01-22T16:00:00+02:00"
}
```

Event fixtures and schemas are in `test/domain-event-fixtures/`.

## Checklist

- [ ] Module name ends with `EventConsumer`
- [ ] Module lives under the appropriate context directory (e.g., `lib/auftragserstellung/` for external events)
- [ ] `@moduledoc false`
- [ ] `use MyApp.EventConsumer` with `routing_key` and `remote_exchange`
- [ ] `handle/2` with default handler parameter (inline or via module attribute)
- [ ] `map_attributes/1` pattern-matches on `@type` array
- [ ] `extract_event_metadata(event)` called and included as `:metadata`
- [ ] `successful_if(:already_persisted)` for idempotency
- [ ] `throw({:retry, error})` for retriable failures
- [ ] Corresponding application service exists to process the event
- [ ] `mix format` passes
