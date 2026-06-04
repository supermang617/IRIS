# Iris Memory Core Phase 1

Status: superseded by the implemented restricted local memory broker and Hermes staging baseline.

Goal: keep Iris memory traceable, correctable, auditable, non-agentic, local, and easy to test.

The current public baseline is intentionally narrower than a full memory product:

- Iris owns the active local memory boundary.
- Hermes can query approved memory only through the loopback Iris broker.
- Hermes can propose memory only into staging.
- Iris/user approval is required before any staged proposal becomes active memory.
- OneDrive is cold archive only, disabled by default, and requires `.iris-memory-archive.enc` archive names.
- Archive export remains unavailable until real encryption is implemented.

Do not add UI panels, settings, SQLite, Postgres, Redis, Docker, Honcho, pgvector, embeddings, background agents, cloud, telemetry, dependencies, unrelated abstractions, unrelated refactors, or unrelated cleanup for memory unless Alejandro explicitly approves the new scope.

Runtime invariant: Iris may store, retrieve, correct, suppress, delete, stage, review, and audit memory only. Iris may not act.

Do not add mouse or keyboard control, clipboard, shell/process execution, browser automation, runtime network calls, plugins, scripting, accessibility/window control, or autonomous computer use.

Implementation notes:

- Validation is structural only.
- Do not sanitize, censor, or normalize away blunt/profane/adult/weird text.
- `DoNotRemember` stores nothing, links nothing, audits nothing, and is never retrieved.
- Duplicate detection is normalized text plus project plus fact kind, and only merges active facts.
- Retrieval returns only active facts and must not return unrelated active high-importance facts when a query is provided.
- Correction requires a real stored correction `MemoryEvent` first.
- Suppression and deletion are status changes, not physical removal.
- Every successful mutation writes exactly the required audit entry.
- Source links must be real, non-empty, and deduplicated.
- The pure-core concept remains useful for future refactors, but it is no longer a deferred blocker for the public baseline.
