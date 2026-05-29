# Project Iris Agent Instructions

This file is for Codex / coding agents working in this repository.

Repo path:

```text
C:\Projects\IRIS

## Critical behavior note

Before writing scripts, read this file and follow it.

Do not repeat known mistakes:
- Do not generate old broken scripts.
- Do not use nonexistent APIs.
- Do not guess crate paths.
- Do not use Read-Host.
- Do not make tests optional.
- Do not overwrite root Cargo.toml incorrectly.
- Do not claim edits were made unless files were actually changed.
- Prefer simple, buildable code over planning.

If unsure, inspect the repo first with:
git status --short
cargo build --workspace
cargo test --workspace

## Audit-file skip rule

The forbidden API audit must not scan files that intentionally document forbidden strings.

Skip:
- AGENTS.md
- capabilities/v0_1_capability_ledger.toml
- xtask/src/main.rs

Reason: those files intentionally contain forbidden words for documentation or audit implementation.

## Local inference rule

Local inference must start as a stub.

Real Ollama or LM Studio support must be added later behind an explicit 127.0.0.1-only boundary.

Do not add network crates without approval.

Do not add runtime network behavior without approval.
