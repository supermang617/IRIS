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

## Repeated Codex mistake rule

Reject generated scripts before running if they contain:
- ../crates/ inside sibling crate dependencies
- Read-Host
- members +=
- [workspace] inside a crate Cargo.toml
- nonexistent types like Text or SharedContext
- fake AssistantReply structs outside iris-core-types
- treating non-Result APIs as Result
- optional cargo tests
- apply_patch JSON
- partial patch fragments

Always provide one full clean PowerShell script, not a patch fragment.

## Local inference documentation rule

iris-local-inference is currently a disabled stub only.

Do not claim Ollama or LM Studio is implemented until real code exists and tests pass.

Do not add network crates without approval.

Do not use Read-Host, optional tests, partial patches, or sibling dependency paths containing ../crates/.

## Local inference config rule

Local inference config may define future loopback endpoint strings only.

Current allowed future endpoint examples:
- 127.0.0.1:<port>
- localhost:<port>

Current local inference behavior remains disabled stub only.

Do not add network crates or perform network calls without explicit approval.

Do not use std::net in runtime crates while the forbidden API audit rejects std::net.

## Network/config boundary rule

Do not use std::net, HTTP/network crates, or real Ollama/LM Studio calls until explicitly approved.

Local inference config may define future 127.0.0.1 or localhost endpoint strings only.

Current inference behavior remains disabled stub unless real loopback integration is explicitly approved.

## Runtime integration rule

For iris-runtime integration:
- Do not import nonexistent Text or SharedContext types.
- ContextGate::gate_user_text returns GatedContextBundle directly, not Result.
- CognitionStub::respond returns AssistantReply directly, not Result.
- AssistantReply lives in iris-core-types and must not be redefined in runtime.
- iris-runtime should coordinate existing crates, not invent local replacement structs.

## Default future model target rule

Future model bootstrapping currently targets abliterated or uncensored Qwen-family GGUF builds from bartowski on Hugging Face as the default candidate source.

This is a design target only.

Do not implement Hugging Face access, model downloading, llama.cpp bindings, hardware probing, Ollama calls, LM Studio calls, or real local inference until explicitly approved.

Before implementation, verify exact repo names, filenames, licenses, quantization, SHA256 hashes, and hardware fit.

Do not assume all Qwen models are abliterated.

Do not assume any specific model file exists until verified.

## Runtime CLI rule

Runtime CLI modes may use std::env::args only.

Do not use nonexistent Text or SharedContext types.

Do not redefine AssistantReply in iris-runtime.

Do not treat ContextGate::gate_user_text or CognitionStub::respond as Result.

Self-check mode is invoked as:
cargo run -p iris-runtime -- self-check

## Line ending rule

Repository text files should use stable Git line endings.

Use `.gitattributes` to keep Rust, TOML, and Markdown files as LF.

Do not change global Git config for line endings without explicit approval.
