# Architecture

Project Iris v0.1 is built as a small Rust workspace.

## Current crates

- iris-core-types: shared types
- iris-policy: static safety constants
- iris-paths: path validation
- iris-redaction: redaction
- iris-context-gate: provenance and authority gate
- iris-cognition: deterministic cognition layer
- iris-local-inference: disabled local inference boundary stub
- iris-runtime: safe coordinator
- xtask: audit

## Current flow

fixed demo input
-> ContextGate::gate_user_text
-> GatedContextBundle
-> CognitionStub::respond
-> LocalInferenceStub::infer
-> runtime output

## Local inference boundary

iris-local-inference is currently disabled.

It does not call Ollama.

It does not call LM Studio.

It does not use networking.

Future real local inference must be explicitly limited to approved 127.0.0.1 local backends.
