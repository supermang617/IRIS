# Project Iris v0.1 Windows Specification

Produced by Alejandro Pinto.

## Core Product Invariant

Safe-mode Iris may see, listen, think, remember with permission, and respond
without acting on the computer. An explicitly approved Agentic Session may
perform supervised local file, PowerShell, and process work under Iris policy.
Agentic browser work is isolated in an Iris-owned profile and remains subject
to confirmation gates for consequential actions.

## Current Track

Iris is a single-user Windows prototype with a local-first runtime. The previous cross-platform roadmap, multi-tier model registry, and dev-vs-user model split are retired for this workspace.

The only configured model identity is:

- `huihui_ai/gemma-4-abliterated:e2b`

This is treated as a local Ollama model name. Iris core remains behind a manifest/provider boundary, but this build does not include fallbacks, hardware-tier routing, Hugging Face downloads, GGUF registry management, model pulling, model auto-selection, critic/worker split, multi-model debate, or background network behavior.

## Hermes Integration

Hermes has Off, Safe, and Agentic Session modes. Safe is the startup default.

- Safe uses `profiles/iris_restricted.json` and exposes Iris-owned memory query,
  staged proposal, and restricted research tools.
- Agentic uses provenance-pinned Hermes Agent 0.18.0 over stdio ACP with
  `profiles/iris_agentic.json`.
- Both modes use the existing Iris Ollama endpoint/model only.
- Agentic exposes `iris_query_memory`, `iris_propose_memory`, `read_file`,
  `write_file`, `patch`, `search_files`, `terminal`, `process`, and the reviewed
  `browser_*` tools.
- Iris is the sole durable memory authority. Hermes cannot promote proposals,
  access raw memory files, or use native durable memory.
- Safe Hermes cannot run commands or edit files. Agentic Hermes may use its
  reviewed local tools after explicit session activation; sensitive,
  destructive, install/admin, credential, and scope-expanding work requires
  separate approval.
- General window automation, clipboard access, cloud-sync storage access, and arbitrary
  plugin loading remain unavailable. Agentic browser automation uses only the
  pinned isolated browser runtime and dedicated profile.

Hermes memory proposals go to staging. Iris/user approval is required before promotion to active memory.

## Memory and Archive Boundary

- Active memory is local and Iris-owned.
- Hermes staging memory is local and Iris-owned.
- Cloud-sync memory storage is not part of v1.
- Archive targets must use `.iris-memory-archive.enc`.
- Live SQLite/JSON memory stores must not be placed under cloud-sync folders.
- Archive export is unavailable until real encryption is implemented.
- Import requires Iris reconciliation.

## Capability Ledger Definition

The capability ledger records what each crate may and may not do. Any architectural change that adds capture, voice, memory, model loading, loopback inference, downloads, system control, broader filesystem access, or external network behavior must update `capabilities/v0_1_capability_ledger.toml` before implementation.

## Runtime Boundaries

- Target platform: Windows.
- Model provider: local Ollama boundary.
- Configured model: `huihui_ai/gemma-4-abliterated:e2b`.
- Context ceiling: `num_ctx = 8192`.
- Vision model: same configured model, no separate model.
- Fallback models: disabled.
- External runtime network: disabled for Iris core and Safe mode except the
  recognized primary-source lookup; Agentic public web access is browser-only.
- IPC: loopback-only.
- System control: unavailable in Safe mode; reviewed local file, PowerShell, and
  process tools are available only in an approved Agentic Session.
- Clipboard access: not present.
- Process execution: Iris-owned helpers plus approved Agentic Session tasks,
  supervised and terminated through Iris.
