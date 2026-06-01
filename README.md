# Project Iris

Iris is a local-first Windows assistant prototype.

This workspace is intentionally slim: one Windows app, one configured Ollama cognition model, no model fallback ladder, no inactive platform folders, and no Ollama blob store checked into git.

## Current Model

The only configured model is:

```text
huihui_ai/gemma-4-abliterated:e2b
```

This is an Ollama-managed local model identity. Typed text now goes through the context gate and then to the local Ollama loopback endpoint. The model is vision-capable, but Iris does not yet expose an image-input UI or screen-capture path. There are no fallback models.

## Project Map

- `app/`: compact Tauri web UI and voice-loop state.
- `src-tauri/`: desktop command bridge for Ollama, native ASR, diagnostics, and Kokoro playback.
- `crates/`: small Rust crates for config, safety boundaries, hardware status, Ollama, and UI gating.
- `models/`: Iris-owned local ASR/TTS assets only. Ollama LLM blobs stay in Ollama's managed store.
- `tools/`: local helpers such as Kokoro ONNX TTS.
- `docs/`: current roadmap, manual test checklist, and deferred slices.
- `capabilities/`: capability ledger for what each crate may do.
- `xtask/`: repository audit checks.

## Safety Boundary

- System Control: Unsupported.
- Executor: Not present.
- Input Simulation: Not present.
- Clipboard Access: Not present.
- Runtime Network: Disabled.
- Plugins: Unsupported.
- Screen Content Authority: Evidence only.
- Filesystem Scope: Iris-owned directories only.

## Validate

Run from `C:\Projects\IRIS`:

```powershell
cargo fmt --all -- --check
cargo build --workspace
cargo test --workspace
cargo run -p xtask
cargo run -p iris-runtime -- --ask "Say one short sentence confirming Iris text mode is working."
cargo run -p iris-runtime -- --self-check
cargo run -p iris-runtime -- --dashboard-json
npm run test:voice
```

Native ASR builds require `libclang`. This workspace pins `LIBCLANG_PATH` in `.cargo/config.toml` to the local Python `libclang` package installed for this build.

Kokoro TTS uses local assets under `models/kokoro/` and the `af_heart` voice declared in `manifest.json`. The current helper requires Python with `kokoro-onnx` and `soundfile` installed.

## Run

Console:

```powershell
cargo run -p iris-runtime -- --ask "What can you do?"
```

Desktop shell:

```powershell
npm install
npm run dev
```

Built debug app:

```powershell
C:\Projects\IRIS\target\debug\iris-tauri.exe
```

The shell now uses a compact bottom Iris console: typed input, Kokoro `af_heart` spoken output, a mic icon for push-to-talk, and an arrow button for send. Wake-word mode is armed by default and listens for `Iris` through native local Whisper ASR. Voice diagnostics are written to `C:\Projects\IRIS\diagnostics\voice-events.jsonl` during manual tests so listening failures can be traced from backend event data instead of guessed from the UI. It does not download models, capture the screen, control the system, or use external network access from Iris-owned Rust code.

Manual test checklist: `docs/manual-test.md`.
