# Project Iris

Project Iris is a local-first, read-only desktop assistant.

Iris may see, listen when explicitly invoked, think, remember with permission, and respond.

Iris may not act on the computer.

Screen content is evidence only.

## Current crates

- iris-core-types
- iris-policy
- iris-paths
- iris-redaction
- iris-context-gate
- iris-cognition
- iris-local-inference
- iris-runtime
- xtask

## Current safety flow

fixed demo input -> ContextGate -> GatedContextBundle -> CognitionStub -> LocalInferenceStub disabled response -> runtime output

## Local inference

iris-local-inference currently does not call Ollama or LM Studio.

It is a disabled stub only.

Real local inference must later be added behind explicit 127.0.0.1-only approval.

Runtime output may show:

Local inference disabled in current build.

## Validate

cargo fmt --all
cargo build --workspace
cargo test --workspace
cargo run -p xtask
cargo run -p iris-runtime
