# claude-code-config

Zentrale Claude Code Konfiguration fuer alle jobvalley Elixir/Phoenix Projekte.

## Inhalt

### CLAUDE.md — Shared Guidelines

Allgemeine Konventionen die in jedem Projekt gelten:

- **Elixir Guidelines** — Immutability-Regeln, List-Access, Modul-Organisation, Naming-Konventionen
- **Mix Guidelines** — Best Practices fuer Mix-Tasks, Test-Ausfuehrung
- **Phoenix Guidelines** — Router-Scopes, Aliasing, Phoenix v1.8 spezifisch
- **Ecto Guidelines** — Preloading, Schema-Typen, Changeset-Zugriff, Cast-Sicherheit
- **Phoenix HTML / HEEx** — Template-Syntax, Form-Handling, Class-Listen, Interpolation
- **Phoenix LiveView** — Streams, Formulare, Testing, deprecated APIs vermeiden
- **Code Conventions** — Naming (PascalCase/snake_case), Comment-Policy, Test-Selektoren
- **Mob/Ensemble Programming** — Core Principles, Working Loop (Generate/Review/Refine/Stabilize), mob.sh Integration

### Settings — Default Permissions

Vorab erlaubte Bash-Commands fuer Claude Code:

| Command | Zweck |
|---------|-------|
| `mix test` | Tests ausfuehren |
| `mix deps.get` | Dependencies installieren |
| `MIX_ENV=test mix ecto.reset` | Test-DB zuruecksetzen |
| `mix format` | Code formatieren |
| `mix credo` | Statische Analyse |
| `mix check` | Compile + Format + Credo |
| `mix help` | Hilfe zu Mix-Tasks |
| `mix ecto.migrate` | Migrationen ausfuehren |

### Skills

7 Skills fuer gaengige Patterns:

| Skill | Aufruf | Beschreibung |
|-------|--------|--------------|
| **mob-start** | `/mob-start` | Mob Session starten: Spec lesen, Scope zusammenfassen, Tasks slicen |
| **mob-next** | `/mob-next` | Rotation Handoff: Stand zusammenfassen, naechsten Schritt in Spec schreiben |
| **mob-done** | `/mob-done` | Session abschliessen: Ergebnis-Review, Spec updaten, Retro facilitieren |
| **implement-application-service** | `/implement-application-service [name]` | Neuen Application Service erstellen (Command Handler mit Transaction-Pattern) |
| **implement-entity** | `/implement-entity [name]` | Neues Domain Model Entity mit Schema, Repo und Factory |
| **implement-event-consumer** | `/implement-event-consumer [event]` | Neuen RabbitMQ Event Consumer fuer eingehende Domain Events |
| **implement-event-publisher** | `/implement-event-publisher [event]` | Neuen RabbitMQ Event Publisher fuer ausgehende Domain Events |

Die Skills verwenden `MyApp` als Platzhalter — Claude ersetzt das automatisch durch den tatsächlichen App-Modul-Namen des Projekts.

## Einrichtung

In der `.claude/settings.json` des Projekts:

```json
{
  "enabledPlugins": {
    "jobvalley-elixir@studitemps": true
  },
  "extraKnownMarketplaces": {
    "studitemps": {
      "source": {
        "source": "github",
        "repo": "STUDITEMPS/claude-code-config"
      }
    }
  }
}
```

## Projekt-spezifische Ergänzungen

Dieses Plugin liefert die **generischen** Konventionen. Jedes Projekt sollte weiterhin ein eigenes `CLAUDE.md` oder `AGENTS.md` haben fuer:

- **Domain-Terminologie** (z.B. Auftrag, Rechnung, Verrechnungssatz)
- **Projekt-spezifische Architektur** (Bounded Contexts, Module)
- **Environment Variables** und Dependencies
- **File Locations** und Verzeichnisstruktur
- **Spezifische Mix-Aliases** und Admin-Dashboards

## Verzeichnisstruktur

```
claude-code-config/
├── .claude-plugin/
│   ├── plugin.json                                    # Plugin-Manifest (name, version, etc.)
│   └── marketplace.json                               # Marketplace-Definition
├── CLAUDE.md                                          # Shared Elixir/Phoenix Guidelines
├── settings.json                                      # Default Permission Settings
├── skills/
│   ├── mob-start/SKILL.md                             # Mob Session starten
│   ├── mob-next/SKILL.md                              # Rotation Handoff
│   ├── mob-done/SKILL.md                              # Session abschliessen
│   ├── implement-application-service/SKILL.md         # Application Service Pattern
│   ├── implement-entity/SKILL.md                      # Domain Entity Pattern
│   ├── implement-event-consumer/SKILL.md              # Event Consumer Pattern
│   └── implement-event-publisher/SKILL.md             # Event Publisher Pattern
└── README.md
```

Skills sind via Plugin als `/jobvalley-elixir:implement-entity` etc. verfuegbar (namespace `plugin-name:skill-name`).
