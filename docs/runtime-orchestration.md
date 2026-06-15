# Iris Runtime Orchestration

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

## Recommended Local Runtime Shape

For v0.1, the best safe runtime shape is:

- The Iris desktop window opens first, then starts Ollama hidden in the
  background when needed and waits for `127.0.0.1:11434` inside the UI.
- Ollama runs as the local model service on `127.0.0.1:11434`.
- Iris runs as the Tauri desktop shell plus Rust command bridge.
- Safe Hermes remains a restricted Iris-owned sidecar, started by Iris for
  local RAG and staged memory-transfer work.
- Agentic Hermes uses pinned Hermes Agent 0.16.0 through a hidden Iris-owned ACP
  child process supervised by a Windows Job Object.
- The Iris memory broker is loopback-only on `127.0.0.1:48731`.
- Dynamic system context runs inline inside Iris with no background process or
  additional model call. It stores only aggregate communication metrics.

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
- Output cap per response: `192` tokens
- Keep alive: `10m`
- Thinking: disabled for Iris runtime calls
- Parallel model streams: `1`
- Fallback models: disabled
- Model auto-selection: disabled
- Model pulling by runtime: disabled
- Hermes enabled by default: true
- Hermes sidecar enabled by default: true
- Hermes research: requires explicit user research request
- Safe Hermes acting tools: none
- Hermes web research: enabled through a restricted text-only search fetcher
- Hermes startup mode: Safe
- Hermes modes: Off, Safe, Agentic Session
- Agentic inactivity expiry: 30 minutes
- Agentic runtime: pinned Hermes Agent 0.16.0 over stdio ACP
- Agentic memory tools: `iris_query_memory`, `iris_propose_memory`
- Agentic action tools: `read_file`, `write_file`, `patch`, `search_files`,
  `terminal`, `process`
- Agentic native durable memory, MCP, lazy installs, and cloud fallback: disabled
- Dynamic context: enabled by default, 30-day half-life, 64-observation cap,
  no raw text storage

These settings intentionally favor reliability and privacy over maximum raw
throughput. Iris, Hermes, and Ollama share one local model path so they do not
fight for VRAM/RAM or create inconsistent answers.

## Hermes Manual Testing

Hermes is enabled for local RAG and web research by default. Start Iris from the normal launcher.
Iris starts the loopback broker and Hermes sidecar when a Hermes task is
submitted. Hermes must pass the runtime tool audit before task execution.

Mode commands are entered through Iris:

- `hermes mode off`
- `hermes mode safe`
- `hermes agentic C:\absolute\workspace`
- `hermes session end`
- `hermes status`

Panic Stop invalidates any Agentic session and forces Off. Clearing Panic Stop
returns to Safe and never restores Agentic mode.

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
- Safe Hermes status reports `iris_query_memory`, `iris_propose_memory`, and `iris_web_research`.
- Agentic Hermes status reports the Iris memory tools and the six reviewed
  action tools.
- Hermes reports `parallelInferenceStreams: 1`.
- An approved Agentic session can complete a local text task, query approved
  Iris memory, stage a memory proposal, and perform approved local file,
  PowerShell, and process work through ACP with provenance and redacted audits.
- Ending the session, changing mode, Panic Stop, or Iris exit terminates ACP.
- Natural online/research requests submitted to Iris route through Hermes.
- Memory proposals remain staged until Iris/user approval.
- `dynamic context` reports the current aggregate communication profile;
  `dynamic context off`, `on`, and `reset` work without changing durable memory.

## What Not To Change

Do not enable:

- external runtime network;
- browser or window automation;
- clipboard access;
- shell/process execution outside an explicitly approved Agentic Session;
- fallback models or model auto-selection;
- parallel Hermes inference streams;
- live memory databases inside OneDrive.

Those changes would weaken the local-only safety model and make manual testing
harder to trust.
