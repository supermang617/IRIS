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

## Hard failure patterns to reject before running Codex scripts

Reject and regenerate any script that contains:

- `Read-Host`
- `apply_patch`
- `members +=`
- `[workspace]` inside any crate Cargo.toml
- sibling dependency paths containing `../crates/`
- fake local `AssistantReply`
- nonexistent `Text`
- nonexistent `SharedContext`
- treating `ContextGate::gate_user_text` as `Result`
- treating `CognitionStub::respond` as `Result`
- optional tests
- partial patch fragments
- unfinished here-strings
- `exit $LASTEXITCODE`
- overwriting AGENTS.md instead of appending to it
- using `std::net` while audit forbids it
- using `std::process::Command`
- adding network/HTTP crates without approval
- claiming Ollama, LM Studio, voice, OCR, TTS, memory DB, or model download is implemented when it is only planned

## Required PowerShell script shape

Every generated PowerShell script must be complete and runnable from a fresh PowerShell window.

Every script must:

- start with `cd "C:\Projects\IRIS"`
- create folders before writing files
- write complete files with here-strings when editing generated code
- avoid fragile regex replacement unless there is no safer option
- run `cargo fmt --all`
- run `cargo build --workspace`
- run `cargo test --workspace`
- run `cargo run -p xtask`
- run `cargo run -p iris-runtime` when runtime behavior or shared types change
- run `cargo run -p iris-runtime -- self-check` when runtime CLI behavior changes
- print `git status --short`
- stage and commit successful changes when the task is complete

## Current known APIs

ContextGate:

- `ContextGate::new()`
- `ContextGate::gate_user_text(&str) -> GatedContextBundle`
- `ContextGate::gate_screen_ocr_text_for_future_use(&str) -> GatedContextBundle`

CognitionStub:

- `CognitionStub::new()`
- `CognitionStub::respond(GatedContextBundle) -> AssistantReply`

LocalInferenceStub:

- `LocalInferenceStub::new_disabled()`
- `LocalInferenceStub::infer(LocalInferenceRequest) -> LocalInferenceResponse`

Current self-check command:

- `cargo run -p iris-runtime -- self-check`

## Current local inference boundary

Current inference is disabled stub behavior only.

Future model target is abliterated or uncensored Qwen-family GGUF builds from bartowski on Hugging Face, but this is a design target only.

Do not implement download, Hugging Face access, Ollama, LM Studio, llama.cpp, hardware probing, or real loopback inference until explicitly approved.

## Model manifest rule

iris-model-manifest is metadata-only.

It must not download models.

It must not call Hugging Face.

It must not call Ollama or LM Studio.

It must not use networking, HTTP crates, std::net, shell execution, process spawning, or filesystem scanning.

Exact model filenames, SHA256 hashes, licenses, and hardware requirements must be verified before real model use.

## Model router rule

iris-model-router is deterministic metadata routing only.

It must not probe hardware.

It must not read files.

It must not download models.

It must not call Hugging Face, Ollama, LM Studio, llama.cpp, or any network API.

It must not use std::net, std::process, shell execution, clipboard access, UI automation, or filesystem scanning.

Current routing targets are placeholders until exact model names, filenames, licenses, SHA256 hashes, and hardware fit are verified.

## Runtime model-plan rule

Runtime model-plan mode is metadata-only.

Current command:
cargo run -p iris-runtime -- model-plan

It may display the future routed Qwen GGUF target for the Windows RTX 4060 class profile.

It must not download models, call Hugging Face, call Ollama, call LM Studio, open sockets, scan hardware, or perform real inference.

## Model store rule

iris-model-store defines safe model path metadata only.

It must not scan the filesystem.

It must not download models.

It must not call Hugging Face, Ollama, LM Studio, llama.cpp, or any network API.

It must reject parent traversal, absolute model filenames, and backslash paths.

Actual model presence checks and file reads must be explicitly approved later.

## Runtime model-store display rule

Runtime model-plan may display planned model storage metadata.

It must not scan the filesystem.

It must not read model files.

It must not download models.

It must not call Hugging Face, Ollama, LM Studio, llama.cpp, or any network API.

## Runtime ask-mode rule

Runtime ask mode is the first command-line testing surface.

Current command:
cargo run -p iris-runtime -- ask "hello iris"

Ask mode must remain read-only and must route text through:
ContextGate -> CognitionStub -> LocalInferenceStub

It must not add UI, OCR, voice, TTS, memory DB, screen capture, networking, shell/process execution, clipboard access, or automation.

## Verification script rule

Use scripts/verify_iris_safety_spine.ps1 as the main local verification command.

It must run:
- cargo fmt --all
- cargo build --workspace
- cargo test --workspace
- cargo run -p xtask
- cargo run -p iris-runtime
- cargo run -p iris-runtime -- self-check
- cargo run -p iris-runtime -- model-plan
- cargo run -p iris-runtime -- ask "hello iris contact@example.com password=secret"

The script is for development verification only. It does not grant runtime shell/process capability.

## Prompt builder rule

iris-prompt owns model prompt construction.

Cognition must build prompts from GatedContextBundle only.

Screen-derived context must remain labeled as UntrustedEvidence in prompts.

Do not pass raw OCR, raw screenshots, raw audio, command requests, or arbitrary files directly into cognition.

## Runtime prompt-preview rule

Runtime prompt-preview is the final dry-run checkpoint before real local inference.

Current command:
cargo run -p iris-runtime -- prompt-preview "hello iris contact@example.com password=secret"

It must route text through:
ContextGate -> GatedContextBundle -> PromptBuilder

It must show the exact model-safe prompt that future local inference would receive.

It must not call Ollama, LM Studio, Hugging Face, llama.cpp, download models, open sockets, read model files, use network APIs, or perform real inference.

## Loopback inference audit boundary rule

The only future file allowed to use std::net for local inference is:
crates/iris-local-inference/src/loopback.rs

That future file may only connect to validated 127.0.0.1 or localhost endpoints.

No other runtime crate may use std::net.

HTTP crates such as reqwest or hyper remain forbidden unless explicitly approved.

This is a preparation step only. It does not implement real local inference yet.

## Minimal Ollama loopback client rule

The only approved local inference network file is:
crates/iris-local-inference/src/loopback.rs

It may use std::net only to connect to validated 127.0.0.1 or localhost endpoints.

It must not use reqwest, hyper, tokio::net, cloud URLs, non-loopback hosts, shell/process execution, clipboard access, or browser automation.

It must not be enabled by default.

Runtime remains disabled stub unless an explicit test command opts into loopback later.

## Runtime Ollama test rule

Runtime Ollama test command:
cargo run -p iris-runtime -- ollama-test <ollama-model-name> "hello iris"

If no model is provided, the command must print usage and make no network call.

If a model is provided, it may call only the explicit 127.0.0.1:11434 Ollama loopback endpoint through iris-local-inference.

This is the first manual local-thinking test surface.

Do not make this the default runtime path yet.

## Local thinking test script rule

Use scripts/test_iris_ollama_loopback.ps1 as the manual local model test command.

It runs the safety checks first, then tests only 127.0.0.1 Ollama loopback.

Example:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_ollama_loopback.ps1 qwen-model-name "hello iris"

This script is a development test helper. It does not make Ollama the default runtime path.

## Selected Qwen2.5-VL test model rule

The selected local test model is:
huihui_ai/qwen2.5-vl-abliterated:3b

Use scripts/setup_iris_qwen_vl_ollama.ps1 to pull it through Ollama and run the first Iris local-thinking test.

Use scripts/test_iris_ollama_loopback.ps1 for repeat tests.

Do not make this model path the default runtime behavior yet.

The default runtime remains disabled stub unless an explicit test command opts into Ollama loopback.

## Selected model smoke test rule

Use scripts/smoke_test_selected_qwen_model.ps1 after the selected Qwen2.5-VL model is installed.

Selected model:
huihui_ai/qwen2.5-vl-abliterated:3b

This is the first repeatable local-thinking smoke test.

## Selected local ask command rule

The first direct local-thinking command is:
cargo run -p iris-runtime -- ask-local "hello iris"

PowerShell helper:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ask_iris_local.ps1 "hello iris"

This command must route through:
ContextGate -> PromptBuilder -> OllamaLoopbackClient

It may only call the selected model through 127.0.0.1 Ollama loopback.

The default runtime remains disabled stub unless ask-local or ollama-test is explicitly used.

## Selected local chat command rule

The first interactive local-thinking command is:
cargo run -p iris-runtime -- chat-local

PowerShell helper:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\chat_iris_local.ps1

One-turn chat test:
cargo run -p iris-runtime -- chat-local "hello iris"

This command must route through:
ContextGate -> PromptBuilder -> OllamaLoopbackClient

It may only call the selected model through 127.0.0.1 Ollama loopback.

The default runtime remains disabled stub unless ask-local, chat-local, or ollama-test is explicitly used.

## Roadmap tracking rule

Use docs/roadmap-v0_1.md and docs/current-track.md to stay on plan.

Current immediate next step:
Panic Stop skeleton.

Do not continue adding voice, TTS, ASR, HUD, OCR, screen capture, memory database, dashboard, or governor work until Panic Stop exists as a tested skeleton.

The first milestone is basic text and voice response:
typed/explicit voice input -> ContextGate -> PromptBuilder -> selected local model -> text response -> local speech output.
