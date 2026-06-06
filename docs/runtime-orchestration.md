# Iris Runtime Orchestration

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

## Recommended Local Runtime Shape

For v0.1, the best safe runtime shape is:

- The Iris launcher starts Ollama hidden/minimized when needed and waits for
  `127.0.0.1:11434`.
- Ollama runs as the local model service on `127.0.0.1:11434`.
- Iris runs as the Tauri desktop shell plus Rust command bridge.
- Hermes remains a restricted Iris-owned sidecar, started by Iris for local RAG
  and staged memory-transfer work.
- The Iris memory broker is loopback-only on `127.0.0.1:48731`.

Hermes should not be a separate visible app that the beginner manually opens.
It should run as a hidden child process owned by Iris, with stdin/stdout JSON
transport, fixed tools, and a startup audit. Ollama should also not require a
separate user action during normal use: opening Iris should start Ollama in the
background when the executable is available.

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
- Hermes enabled by default: true
- Hermes sidecar enabled by default: true
- Hermes research: requires explicit user research request
- Hermes acting tools: none
- Hermes web research: enabled through a restricted text-only search fetcher

These settings intentionally favor reliability and privacy over maximum raw
throughput. Iris, Hermes, and Ollama share one local model path so they do not
fight for VRAM/RAM or create inconsistent answers.

## Hermes Manual Testing

Hermes is enabled for local RAG and web research by default. Start Iris from the normal launcher.
Iris starts the loopback broker and Hermes sidecar when a Hermes task is
submitted. Hermes must pass the runtime tool audit before task execution.

Use these desktop commands:

```powershell
hermes status
hermes: summarize what you know from memory
hermes research: find relevant approved memory about Iris testing
look online for the latest Ollama release
hermes code: suggest the smallest fix for the current failing check
hermes staging
hermes accept <number>
hermes reject <number>
```

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
- Hermes status reports only `iris_query_memory`, `iris_propose_memory`, and `iris_web_research`.
- Hermes reports `parallelInferenceStreams: 1`.
- Hermes reports no acting tools.
- Natural online/research requests submitted to Iris route through Hermes.
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
