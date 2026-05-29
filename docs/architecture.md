# Architecture

Current flow:

fixed demo input
-> ContextGate::gate_user_text
-> GatedContextBundle
-> CognitionStub::respond
-> runtime output

Current crates:

- iris-core-types: shared types
- iris-policy: static safety constants
- iris-paths: path validation
- iris-redaction: redaction
- iris-context-gate: provenance and authority gate
- iris-cognition: deterministic stub
- iris-runtime: safe coordinator
- xtask: audit
