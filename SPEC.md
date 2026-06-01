# Project Iris v0.1 Windows Specification

## Core Product Invariant

Iris may see, listen, think, remember with permission, and respond. Iris may not act on the computer.

## Current Track

Iris is now a single-user Windows prototype. The previous cross-platform roadmap, multi-tier model registry, and dev-vs-user model split are retired for this workspace.

The only configured model identity is:

- `huihui_ai/gemma-4-abliterated:e2b`

This is treated as a local Ollama model name. Iris core remains behind a manifest/provider boundary, but this build does not include fallbacks, hardware-tier routing, Hugging Face downloads, GGUF registry management, or background network behavior. The configured model is vision-capable, and future image/vision work must use this same unified model rather than adding a separate vision model.

## Capability Ledger Definition

The capability ledger records what each crate may and may not do. Any future architectural change that adds capture, voice, memory, model loading, loopback inference, downloads, system control, or broader filesystem access must update `capabilities/v0_1_capability_ledger.toml` before implementation.

## Runtime Boundaries

- Target platform: Windows.
- Model provider: local Ollama boundary.
- Configured model: `huihui_ai/gemma-4-abliterated:e2b`.
- Context ceiling: `num_ctx = 8192`.
- Vision model: same configured model, no separate model.
- Fallback models: disabled.
- External runtime network: disabled.
- IPC: loopback-only when future local inference is enabled.
- System control: unsupported.
- Clipboard access: not present.
- Process execution: not present.
