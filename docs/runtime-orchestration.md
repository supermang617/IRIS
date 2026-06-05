# Iris Runtime Orchestration

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

## Recommended Local Runtime Shape

For v0.1, the best safe runtime shape is:

- Ollama runs as the local model service on `127.0.0.1:11434`.
- Iris runs as the Tauri desktop shell plus Rust command bridge.
- Hermes remains a restricted Iris-owned sidecar, started by Iris only when the
  Hermes environment gates are explicitly enabled.
- The Iris memory broker is loopback-only on `127.0.0.1:48731` when enabled.

Hermes should not be a separate visible app that the beginner manually opens.
It should run as a hidden child process owned by Iris, with stdin/stdout JSON
transport, fixed tools, and a startup audit. Ollama may run minimized or as the
normal Ollama background app because it is the local model server.

## Default v0.1 Settings

These are the safest universal settings for the current model and hardware
target:

- Ollama model: `huihui_ai/gemma-4-abliterated:e2b`
- Ollama endpoint: `http://127.0.0.1:11434/api/generate`
- Context ceiling: `8192`
- Output cap per response: `384` tokens
- Keep alive: `10m`
- Thinking: disabled for Iris runtime calls
- Parallel model streams: `1`
- Fallback models: disabled
- Model auto-selection: disabled
- Model pulling by runtime: disabled
- Hermes enabled by default: false
- Hermes sidecar enabled by default: false
- Hermes research: requires explicit user research request
- Hermes acting tools: none
- Memory broker external network: none

These settings intentionally favor reliability and privacy over maximum raw
throughput. Iris, Hermes, and Ollama share one local model path so they do not
fight for VRAM/RAM or create inconsistent answers.

## Enabling Hermes For Manual Testing

Hermes is currently a gated test feature. To test it from a developer checkout,
set:

```powershell
$env:IRIS_HERMES_ENABLED="true"
$env:IRIS_HERMES_SIDECAR_ENABLED="true"
$env:IRIS_HERMES_MEMORY_BROKER_ENABLED="true"
```

Then start Iris from the repo or release. Iris is responsible for starting the
Hermes sidecar when a Hermes task is submitted. Hermes must pass the runtime
tool audit before it is allowed to answer.

Do not configure Hermes as a Windows startup app yet. It should not run without
Iris because Iris owns the safety policy, memory broker, and final response
path.

## Manual Test Expectations

When all pieces are healthy:

- `ollama list` shows `huihui_ai/gemma-4-abliterated:e2b`.
- Ollama reports `vision` in the configured model capabilities before claiming
  the image-probe milestone is ready.
- Iris preflight reports Ollama/model PASS.
- Iris text ask returns a short local response.
- Iris image probe describes the known local test image.
- Hermes status reports only `iris_query_memory` and `iris_propose_memory`.
- Hermes reports `parallelInferenceStreams: 1`.
- Hermes reports no acting tools.
- Memory proposals remain staged until Iris/user approval.

## What Not To Change

Do not enable:

- external runtime network;
- browser or window automation;
- clipboard access;
- shell/process execution tools exposed to Iris or Hermes;
- fallback models or model auto-selection;
- parallel Hermes inference streams;
- live memory databases inside OneDrive.

Those changes would weaken the local-only safety model and make manual testing
harder to trust.
