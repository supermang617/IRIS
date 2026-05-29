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
- iris-runtime
- xtask

## Current safety flow

fixed demo input -> ContextGate -> GatedContextBundle -> CognitionStub -> runtime output

## Validate

cargo fmt --all
cargo build --workspace
cargo test --workspace
cargo run -p xtask
cargo run -p iris-runtime
