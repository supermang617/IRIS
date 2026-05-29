# Capability Ledger

Ledger path:

capabilities/v0_1_capability_ledger.toml

The ledger documents allowed and forbidden capabilities per crate.

## Local inference

iris-local-inference is currently a disabled stub.

Allowed capabilities:

- disabled_inference_stub
- future_loopback_boundary_definition
- deterministic_stub_response

Forbidden capabilities:

- runtime_network
- cloud_api
- telemetry
- process_execution
- shell_execution
- browser_automation
- plugin_loading

Real Ollama or LM Studio support must be added later behind explicit 127.0.0.1-only approval.

## Audit

xtask verifies that the ledger exists and scans source files for forbidden runtime/API strings.

Policy and documentation files are skipped because they intentionally document forbidden terms.
