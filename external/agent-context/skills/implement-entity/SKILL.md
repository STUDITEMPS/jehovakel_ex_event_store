---
name: implement-entity
description: Implement a new domain model entity with schema, repository, and factory following the established jobvalley patterns. Use when creating a new bounded context entity, adding a new Ecto schema with its repo and factory, or scaffolding domain model files.
argument-hint: "[entity-name]"
---

# Implement a New Domain Model Entity

When implementing a new entity in `lib/<app_name>/domain_model/`, create **three files** following the established patterns. The entity name (`$ARGUMENTS`) should be in German, snake_case.

## File Structure

Create a new directory under `domain_model/` with these files:

```
lib/<app_name>/domain_model/[entity]/
  ├── [entity].ex             # Schema/Model definition
  ├── [entity]_repo.ex        # Repository (data access)
  └── [entity]_factory.ex     # Factory (test data)
```

Optionally also create: `*_query.ex` (complex query builders), embedded value objects (e.g., `anschrift.ex`).

## 1. Model/Schema File (`[entity].ex`)

Use `MyApp.Includes, :domain_model`, which provides `Ecto.Schema`, `@type t :: %__MODULE__{}`, and `@timestamps_opts [type: :utc_datetime]`.

```elixir
defmodule MyApp.MyEntity do
  @moduledoc false
  use MyApp.Includes, :domain_model

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "table_name" do
    field(:some_field, :string)
    field(:another_field, :integer)
    field(:lock_version, :integer, default: 1)

    timestamps()
  end

  def new(opts) do
    %__MODULE__{
      id: Shared.UUID.generate(),
      some_field: Keyword.get(opts, :some_field)
    }
  end

  def mit_some_field(%__MODULE__{} = entity, value) do
    %__MODULE__{entity | some_field: value}
  end
end
```

### Required patterns

- `use MyApp.Includes, :domain_model` (or `:abrechnungsmodalitaet` for billing modalities)
- `@moduledoc false`
- `@primary_key {:id, :binary_id, autogenerate: true}` (or `autogenerate: false` if IDs come from external systems)
- `field(:lock_version, :integer, default: 1)` — required for the repository's `insert_or_update()` to decide between insert and update via optimistic locking
- `timestamps()` at the **end** of the schema block — generates `inserted_at`/`updated_at` as `:utc_datetime`
- Domain methods use builder/fluent pattern: `new()`, `mit_*()`, `erfassen()`, `loeschen()`
- Never use raw struct updates outside the module — expose `mit_*` functions instead

### Common field types

- Money: `field(:betrag, Money.Ecto.Amount.Type, source: :betrag_in_cents)`
- Enums: `field(:status, Shared.EnumType, enum: MyEnum)`
- Embeds: `embeds_one(:anschrift, Anschrift, on_replace: :delete)`
- Custom Ecto types: `MyApp.Ecto.Interval`, `MyApp.Ecto.Term`, `MyApp.Ecto.Daterange`
- Virtual fields: `field(:computed, {:array, Term}, virtual: true)`
- Soft delete: `field(:geloescht_am, :utc_datetime)` with `use MyApp.SoftDelete.Includes`

### Embedded value objects

Use `@primary_key false` + `embedded_schema` for value objects embedded in a parent:

```elixir
defmodule MyApp.MyEntity.SubEntity do
  @moduledoc false
  use MyApp.Includes, :domain_model

  @primary_key false
  embedded_schema do
    field(:name, :string)
  end

  def new(params) when is_map(params) do
    struct!(__MODULE__, Map.take(params, __schema__(:fields)))
  end
end
```

### Abrechnungsmodalitaeten variant

Billing modalities (like Rechnungsturnus, Zahlungsziel, Versandadresse) use the `:abrechnungsmodalitaet` include instead:

```elixir
use MyApp.Includes, :abrechnungsmodalitaet
```

This extends `:domain_model` and injects shared methods via `@before_compile`: `vordefiniert?/1`, `fuer_auftrag/2`, `fuer_sva/2`. Note: the shared fields (`auftragsnummer`, `sva_id`, `gueltig_ab`, `geloescht_am`, `lock_version`) must still be defined in each model's schema individually.

## 2. Repository File (`[entity]_repo.ex`)

Use `MyApp.Includes, :repository`, which provides `Ecto.Changeset`, `Ecto.Query`, `Repo`, `Ecto.Multi`, and helper functions `cast/2`, `insert_or_update/1`, `reset_embeds_one/2`.

```elixir
defmodule MyApp.MyEntityRepo do
  use MyApp.Includes, :repository

  alias MyApp.MyEntity

  @permitted_params [
    :some_field,
    :another_field
  ]

  def persistiere_my_entity(%MyEntity{} = entity) do
    entity
    |> cast(@permitted_params)
    |> insert_or_update()
  end

  def my_entity_fuer_id(id) when is_binary(id) do
    Repo.get(MyEntity, id)
  end

  def hole_my_entity(id) do
    case my_entity_fuer_id(id) do
      %MyEntity{} = entity -> {:ok, entity}
      nil -> {:error, :my_entity_nicht_gefunden}
    end
  end
end
```

### Required patterns

- `use MyApp.Includes, :repository`
- `@permitted_params [...]` module attribute listing all castable fields (do NOT include `lock_version`, `id`, `inserted_at`, `updated_at`)
- `persistiere_*` function uses `cast(@permitted_params) |> insert_or_update()`
- The `cast/2` helper builds a changeset from a struct, automatically handling `NotLoaded` associations and forcing changes for default values
- `insert_or_update/1` uses `lock_version` to decide: version=1 means insert, version>1 means update, with optimistic locking
- Lookup functions follow naming: `*_fuer_id/1` (returns struct or nil), `hole_*/1` (returns `{:ok, struct}` or `{:error, :not_found_atom}`)

### Special patterns

- Unique `gueltig_ab` constraints (for abrechnungsmodalitaeten): `insert_or_update(mit_gueltig_ab_unique_constraint: @index_names)`
- Embedded entities: use `cast_embed/3` with custom casting functions and `reset_embeds_one/2` to set embedded to nil
- Bulk operations: use `Multi.insert_all()` chunked by 1000 (manually set `inserted_at`/`updated_at` since `insert_all` skips Ecto callbacks)

## 3. Factory File (`[entity]_factory.ex`)

Factories are for test data creation only.

```elixir
defmodule MyApp.MyEntityFactory do
  @moduledoc false
  import MyApp.Factory

  alias MyApp.MyEntity

  def fake_my_entity(opts \\ []) do
    MyApp.Factory.nur_erlaubte_optionen_erlauben!(
      [:id, :some_field, :another_field, :persistiert],
      opts
    )

    entity = MyEntity.new(some_field: Faker.Lorem.word())

    entity =
      if value = Keyword.get(opts, :some_field) do
        MyEntity.mit_some_field(entity, value)
      else
        entity
      end

    if Keyword.get(opts, :persistiert) do
      {:ok, entity} = MyApp.MyEntityRepo.persistiere_my_entity(entity)
      entity
    else
      entity
    end
  end
end
```

### Required patterns

- `import MyApp.Factory`
- `nur_erlaubte_optionen_erlauben!/2` as the first call to validate allowed option keys
- Build entity using domain model builder methods (`new()`, `mit_*()`) — never raw struct manipulation
- Support `:persistiert` option to optionally persist to the database
- Use `Faker` for sensible defaults, `Shared.UUID.generate()` for IDs
- Use `Keyword.get_lazy/3` for expensive default computations

## Checklist

Before finishing, verify:

- [ ] Model has `@moduledoc false`
- [ ] Model uses `use MyApp.Includes, :domain_model`
- [ ] Model has `@primary_key` declaration
- [ ] Model has `field(:lock_version, :integer, default: 1)`
- [ ] Model has `timestamps()` at the end of the schema block
- [ ] Model exposes builder functions (`new`, `mit_*`), not raw struct access
- [ ] Repo uses `use MyApp.Includes, :repository`
- [ ] Repo defines `@permitted_params` (excludes `lock_version`, `id`, timestamps)
- [ ] Repo `persistiere_*` uses `cast(@permitted_params) |> insert_or_update()`
- [ ] Factory uses `import MyApp.Factory`
- [ ] Factory calls `nur_erlaubte_optionen_erlauben!/2`
- [ ] Factory supports `:persistiert` option
- [ ] A corresponding Ecto migration exists for the new table
- [ ] `mix format` passes
