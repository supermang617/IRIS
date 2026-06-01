# Iris Memory Core Phase 1

Status: deferred until text, wake-word, interruption, and local voice turn flow are stable.

Goal: barebones local in-memory memory core that is traceable, correctable, auditable, non-agentic, and easy to test.

Do not add UI, buttons, panels, dashboards, modes, settings, SQLite, Postgres, Redis, Docker, Honcho, pgvector, embeddings, LLM deriver, semantic search, background agents, cloud, telemetry, dependencies, unrelated abstractions, unrelated refactors, or unrelated cleanup.

Keep only these concepts:

- `MemoryEvent`
- `MemoryFact`
- `MemorySource`
- `MemoryAuditEntry`

Keep only these functions:

- `store_event()`
- `merge_or_insert_fact()`
- `retrieve_relevant_facts()`
- `correct_fact()`
- `supppress_fact()`
- `delete_fact()`
- `audit_memory_change()`

Runtime invariant: Iris may store, retrieve, correct, suppress, delete, and audit memory only. Iris may not act.

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
- The pure core uses `&mut self`; thread safety belongs later at runtime integration.
