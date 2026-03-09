---
name: implement-event-publisher
description: Implement a new event publisher to publish domain events to other bounded contexts over RabbitMQ. Use when a new domain event needs to be communicated externally, or when adding a new outgoing event type.
argument-hint: "[event-name]"
---

# Implement a New Event Publisher

Event publishers broadcast domain events from the application to other bounded contexts over RabbitMQ. The event name (`$ARGUMENTS`) should be in kebab-case matching the routing key format (e.g., `rechnung-gestellt`).

## File Structure

```
lib/<app_name>/
  └── [domain]/
      └── [use_case]/
          └── [event_name]_event_publisher.ex
```

Publisher files live alongside the application service that triggers the event.

## Template

### Simple pattern (using `add_metadata/2`)

```elixir
defmodule MyApp.Events.MyEventPublisher do
  @moduledoc false
  use Shared.EventPublisher,
    subscription_key: "MyEventPublisher"

  alias MyApp.Events.MyDomainEvent

  @publisher_options routing_key: "<app-name>.my-event-name"

  def publish(%MyDomainEvent{} = event, metadata, client) do
    event
    |> to_external_event(metadata)
    |> publish_event(client)
  end

  def to_external_event(event, metadata) do
    add_metadata(
      %{
        "describes_action" => %{
          "@id" => Shared.URN.generate(:<app_name>, :entity, event.entity_id),
          "some_field" => event.some_field
        },
        "@type" => [
          "https://studitemps.tech/specification/<app-name>/my-event-name",
          "https://studitemps.tech/specification/domain-event"
        ],
        "@id" => to_external_id(metadata.event_id),
        "unreliable_debugging_data" => %{}
      },
      metadata
    )
  end

  defp to_external_id(event_id) do
    "tech.studitemps:<app-name>:my-event-name:" <> event_id
  end
end
```

### Advanced pattern (using `Shared.EventMetadata.map_metadata/3`)

```elixir
defmodule MyApp.Events.MyEventPublisher do
  @moduledoc false
  use Shared.EventPublisher,
    subscription_key: "MyEventPublisher"

  @publisher_options routing_key: "<app-name>.my-event-name"

  def publish(%MyApp.Events.MyDomainEvent{} = event, metadata, client) do
    event
    |> map_to_external_event(metadata)
    |> publish_event(client)
  end

  def map_to_external_event(event, metadata) do
    Shared.EventMetadata.map_metadata(
      %{
        "describes_action" => %{
          "some_field" => event.some_field,
          "fuer_auftrag" => MyApp.Auftrag.auftrag_id_fuer(event.auftragsnummer),
          "gueltig_ab" => Date.to_iso8601(event.gueltig_ab)
        },
        "@type" => [
          "https://studitemps.tech/specification/<app-name>/my-event-name",
          "https://studitemps.tech/specification/domain-event"
        ]
      },
      metadata,
      event_name: "my-event-name",
      command_name: "my-command-name"
    )
  end
end
```

## What `use Shared.EventPublisher` Provides

- Wraps `Shared.EventStoreListener` for event store subscription
- `import Shared.EventPublisher.MapMetadata` — provides:
  - `add_metadata/2` — merges standard metadata (`caused_by`, `correlates_with`, `occurred_at`, `enacted_by`) into event map
  - `map_metadata/1` — transforms internal metadata to external format
- `publish_event/3` (overridable, third arg defaults to `@publisher_options`) — publishes the event map to RabbitMQ. Typically called as `publish_event(client)` in a pipeline
- `init/1` — initializes publisher state with RabbitMQ client
- `handle/3` — delegates to your `publish/3`

## Required Patterns

- `use Shared.EventPublisher` with `subscription_key` (unique string identifier)
- `@moduledoc false`
- `@publisher_options routing_key: "<app-name>.event-name"` — the RabbitMQ routing key
- `publish/3` — receives `(event, metadata, client)`, transforms and publishes
- `to_external_event/2` or `map_to_external_event/2` — builds the external event map
- When using `add_metadata/2` (simple pattern): define `to_external_id/1` per-publisher to generate the `@id` field:
  ```elixir
  defp to_external_id(event_id) do
    "tech.studitemps:<app-name>:event-name:" <> event_id
  end
  ```
- When using `Shared.EventMetadata.map_metadata/3` (advanced pattern): `@id` is generated automatically — no `to_external_id/1` needed
- URN format for all IDs: `tech.studitemps:CONTEXT:TYPE:IDENTIFIER`
  - Use `Shared.URN.generate/3` to create URNs

## Event Structure Reference

All outgoing events must follow the standard structure:

```json
{
  "@type": [
    "https://studitemps.tech/specification/<APP-NAME>/EVENT-NAME",
    "https://studitemps.tech/specification/domain-event"
  ],
  "@id": "tech.studitemps:<app-name>:event-name:uuid",
  "caused_by": "tech.studitemps:...:uuid",
  "correlates_with": "tech.studitemps:...:uuid",
  "occurred_at": "2024-01-22T16:00:00+02:00"
}
```

Document new events in `test/domain-event-fixtures/bounded-contexts/<app-name>/events/`.

## Checklist

- [ ] Module name ends with `EventPublisher` under `MyApp.Events`
- [ ] `@moduledoc false`
- [ ] `use Shared.EventPublisher` with unique `subscription_key`
- [ ] `@publisher_options` with `routing_key` set
- [ ] `publish/3` implemented with `(event, metadata, client)` signature
- [ ] Event map includes `@type` array with specification URL and `domain-event` URL
- [ ] Event map includes `@id` (via `to_external_id/1` for simple, or auto-generated for advanced)
- [ ] Metadata merged via `add_metadata/2` (simple) or `Shared.EventMetadata.map_metadata/3` (advanced)
- [ ] `publish_event(client)` called to send to RabbitMQ
- [ ] Event fixture documented in `test/domain-event-fixtures/`
- [ ] `mix format` passes
