# Project Iris v0.1 Windows Specification

Produced by Alejandro Pinto.

## Core Product Invariant

Iris may see, listen, think, remember with permission, and respond. Iris may not act on the computer.

## Current Track

Iris is a single-user Windows prototype with a local-first runtime. The previous cross-platform roadmap, multi-tier model registry, and dev-vs-user model split are retired for this workspace.

The only configured model identity is:

- `huihui_ai/gemma-4-abliterated:e2b`

This is treated as a local Ollama model name. Iris core remains behind a manifest/provider boundary, but this build does not include fallbacks, hardware-tier routing, Hugging Face downloads, GGUF registry management, model pulling, model auto-selection, critic/worker split, multi-model debate, or background network behavior.

## Hermes Integration

Hermes is integrated as a restricted local reasoning sidecar foundation.

- Disabled by default.
- Uses `profiles/iris_restricted.json`.
- Uses the existing Iris Ollama endpoint/model only.
- Exposes only `iris_query_memory` and `iris_propose_memory`.
- Runs sequential text tasks only.
- Cannot expose acting tools.
- Cannot write active memory.
- Cannot access raw memory files.
- Cannot access OneDrive.
- Cannot run commands, edit files, control browsers/windows, use clipboard, or operate the computer.

Hermes memory proposals go to staging. Iris/user approval is required before promotion to active memory.

## Memory and Archive Boundary

- Active memory is local and Iris-owned.
- Hermes staging memory is local and Iris-owned.
- OneDrive sync is disabled by default.
- OneDrive is cold archive only.
- Archive targets must use `.iris-memory-archive.enc`.
- Live SQLite/JSON memory stores must not be placed under OneDrive.
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
- External runtime network: disabled.
- IPC: loopback-only.
- System control: unsupported.
- Clipboard access: not present.
- Process execution: not present except approved local helper processes owned by Iris runtime, such as Kokoro TTS and restricted Hermes sidecar startup.
