# Project Iris

Produced by Alejandro Pinto.

Project Iris is a local-first Windows assistant prototype. Iris may see, listen, think, remember with permission, and respond. Iris may not act on the computer.

This repository is public and source-first so people can inspect, test, and submit narrow fixes. Contributions should stay focused on bug fixes, safety-preserving diagnostics, documentation fixes, compatibility repairs, and tests for existing behavior unless Alejandro explicitly approves a broader feature change.

Contact: super.mangmail@gmail.com

## Current Runtime

- Platform: Windows.
- UI shell: Tauri.
- Text and vision model provider: local Ollama loopback.
- Configured model: `huihui_ai/gemma-4-abliterated:e2b`.
- TTS: Kokoro ONNX through the local Python helper, voice `af_heart`.
- ASR: local Whisper model at `models/whisper/ggml-tiny.en.bin`.
- Memory: Iris-owned local memory plus a restricted Hermes broker/staging path.
- Hermes: optional restricted text-only sidecar, disabled by default.
- OneDrive archive policy: cold archive only, encrypted archive names must end with `.iris-memory-archive.enc`.

No fallback models, model pulling, model auto-selection, critic/worker split, multi-model debate, external runtime network, clipboard access, browser automation, or computer control are enabled.

## What Iris Is Becoming

Iris is built to get more useful over time without making the user less safe.
The design goal is a personal assistant that can pick up context from
user-approved memory, grow with the person, and remain local-first. The current
release already separates direct user instructions from untrusted evidence such
as images, documents, screen text, memory search results, Hermes output, and
model output. That boundary keeps prompt injection from becoming permission to
act, expose private context, or rewrite memory.

Iris, Hermes, and OneDrive have separate roles. Iris owns active local memory and
the final response path. Hermes is a restricted text-only helper that can query
approved memory and propose staged memory, but cannot write active memory or act
on the computer. OneDrive is currently limited to encrypted cold-archive policy;
future releases can build toward user-approved memory restore across machines
without putting live memory databases directly in OneDrive.

## Project Map

- `app/`: compact Tauri web UI and voice-loop state.
- `src-tauri/`: desktop command bridge for Ollama, native ASR, diagnostics, Kokoro playback, local memory, and restricted Hermes lifecycle commands.
- `crates/`: Rust crates for config, policy, paths, redaction, context gating, cognition boundaries, hardware status, Ollama, status, UI, and runtime.
- `plugins/`: restricted Hermes sidecar/provider code. These are local text-only helpers, not an acting plugin system.
- `profiles/`: restricted Hermes profile and policy metadata.
- `models/`: Iris-owned local ASR/TTS assets only. Ollama LLM blobs stay in Ollama's managed store.
- `tools/`: local helpers such as Kokoro ONNX TTS.
- `docs/`: download instructions, installer flow, manual testing, roadmap, and memory boundary notes.
- `capabilities/`: capability ledger for crate permissions.
- `xtask/`: repository audit checks.

## Safety Boundary

- System Control: Unsupported.
- Executor: Not present.
- Input Simulation: Not present.
- Clipboard Access: Not present.
- Runtime External Network: Disabled.
- Browser/Window Automation: Not present.
- Plugin Loading: Unsupported.
- Screen Content Authority: Evidence only.
- Filesystem Scope: Iris-owned directories only.

Hermes may query approved Iris memory through the local broker and may propose memory into staging. The only exposed Hermes tools are `iris_query_memory` and `iris_propose_memory`. Hermes cannot write active memory, access raw memory files, access OneDrive, edit files, run commands, control browsers/windows, use the clipboard, or operate the computer.

## Validate

Run from `C:\Projects\IRIS`:

```powershell
cargo fmt --all -- --check
cargo build --workspace
cargo test --workspace
cargo clippy --workspace
cargo run -p xtask
cargo run -p iris-runtime -- --self-check
cargo run -p iris-runtime -- --dashboard-json
npm run test:voice
scripts\test_vision_text_diagnostics.ps1
scripts\test_release_model_e2e.ps1
scripts\iris_preflight_wizard.ps1
scripts\iris_setup_wizard.ps1 -NonInteractive
scripts\test_windows_installer.ps1
git diff --check
```

Native ASR builds require `libclang`. This workspace pins `LIBCLANG_PATH` in `.cargo/config.toml` to the local Python `libclang` package installed for this build.

Kokoro TTS uses local assets under `models/kokoro/` and the `af_heart` voice declared in `manifest.json`. The current helper requires Python with `kokoro-onnx` and `soundfile` installed.

## Run

Download and setup guide: `docs/download-and-run.md`.
Architecture notes: `docs/iris-architecture.md`.
Beginner preflight guide: `docs/installer-preflight.md`.
Windows installer plan: `docs/windows-installer.md`.
The portable release includes `Iris Setup Wizard.bat` for beginner setup and
`Check Iris Preflight.bat` for read-only diagnostics.

Console:

```powershell
cargo run -p iris-runtime -- --ask "What can you do?"
```

Desktop shell:

```powershell
npm install
npm run dev
```

Manual Windows launcher:

```powershell
C:\Projects\IRIS\Start Iris.vbs
```

Manual test checklist: `docs/manual-test.md`.

Diagnostics:

- `diagnostics/manual-launch.log`
- `diagnostics/voice-events.jsonl`
- `diagnostics/voice-latency.txt`

## Public Use

This code is provided for local testing, learning, and bug-fix collaboration. Before publishing, confirm third-party model and asset licenses for anything you redistribute. Ollama model blobs, Kokoro model files, Whisper model files, and other downloaded assets may have their own license terms and should not be assumed to be covered by this repository license.

The root `package.json` remains marked `"private": true` to prevent accidental npm publication. That does not limit GitHub source access, cloning, local testing, or pull requests.
