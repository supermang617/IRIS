# Project IRIS

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

IRIS is a local-first Windows assistant. Iris sees, listens, thinks, speaks, and can remember with permission. 

This repository is public and source-first so people can inspect, test, and submit narrow fixes. Contributions should stay focused on bug fixes, safety-preserving diagnostics, documentation fixes, compatibility repairs, and tests for existing behavior.

## Current Runtime

- Platform: Windows.
- UI shell: Tauri.
- Text and vision model provider: local Ollama loopback.
- Configured model: `huihui_ai/gemma-4-abliterated:e2b`.
- TTS: Kokoro ONNX through the local Python helper, voice `af_heart`.
- ASR: local Whisper model at `models/whisper/ggml-tiny.en.bin`.
- Document-image OCR: local Tesseract OCR.
- Memory: Iris-owned local memory with restricted Hermes broker/staging path.
- Hermes: Safe mode uses the restricted Iris-owned local RAG sidecar, enabled for local memory query/proposal by default. Agentic Session uses pinned Hermes Agent 0.16.0 through an Iris-supervised local ACP bridge.
- Hermes modes: Off, Safe, and Agentic Session are implemented. Safe is the startup default. Agentic supports supervised local text, file, PowerShell, process, and isolated browser tasks plus Iris-owned RAG and staged memory proposals.
- OneDrive archive: cold, encrypted archive names must end with `.iris-memory-archive.enc`.

## Future of IRIS

Iris is built to be more useful over time without compromising users safety.
The design is a personal assistant that can pick up context from
users approved memory, grow, and remain local. The current
release separates user instructions from untrusted evidence such
as images, documents, screen text, memory search results, Hermes output, and
model output. The boundary keeps prompt injection from becoming permissive.

Iris, Hermes, and RAG/OneDrive have separate roles. Iris owns your local memory and
the final response path. Safe Hermes is a restricted text-only helper that can query
approved memory and propose staged memory. Agentic Hermes provides supervised local ACP
reasoning and approval-gated file, PowerShell, process, and isolated browser work through the same
Iris-owned RAG and staging authority.
OneDrive is limited to an encrypted cold-archive;
future releases should build toward user-approved memory restore across machines
without putting live memory databases directly in OneDrive.

## Project Map

- `app/`: compact Tauri web UI and voice-loop state.
- `src-tauri/`: desktop command bridge for Ollama, native ASR, diagnostics, Kokoro playback, local memory, and restricted Hermes lifecycle commands.
- `crates/`: Rust crates for config, policy, paths, redaction, context gating, cognition boundaries, hardware status, Ollama, status, UI, and runtime.
- `plugins/`: restricted Safe Hermes helpers and the Iris-owned official Hermes ACP launcher.
- `profiles/`: Safe, Agentic, and pinned Hermes runtime policy metadata.
- `models/`: Iris-owned local ASR/TTS assets only. Ollama LLM blobs stay in Ollama's managed store.
- `tools/`: local helpers such as Kokoro ONNX TTS.
- `docs/`: download instructions, installer flow, manual testing, roadmap, and memory boundary notes.
- `capabilities/`: capability ledger for crate permissions.
- `xtask/`: repository audit checks.

## Safety Boundary

- System Control: Unsupported outside an explicitly approved Agentic Session.
- Executor: Agentic Session only, supervised through Iris.
- Input Simulation: Not present.
- Clipboard Access: Not present.
- Runtime External Network: Disabled in Iris and Safe Hermes; Agentic browser
  sessions may access public HTTP/HTTPS through the isolated browser runtime.
- Browser Automation: Agentic Session only, using a dedicated Iris-owned profile.
- General Window Automation: Not present.
- Plugin Loading: Unsupported.
- Screen Content Authority: Evidence only.
- Filesystem Scope: Iris-owned directories in Safe mode; selected Agentic workspace
  by default, with separate approval for scope expansion.

Hermes queries approved Iris memory through the local broker, proposes memory into staging, and performs explicit user-requested web research. The exposed Safe-mode Hermes tools are `iris_query_memory`, `iris_propose_memory`, and `iris_web_research`.

Hermes mode state is process-local. Panic Stop forces Off and invalidates any Agentic session. Clearing Panic Stop returns to Safe. Agentic sessions require an absolute workspace path and expire after 30 minutes of inactivity; their workspace boundary is advisory because Agentic PowerShell is not OS-sandboxed.

The Agentic ACP runtime is repo-owned under `.iris-runtime/hermes`, uses local
Ollama only, disables runtime package installation, durable Hermes memory, MCP,
and unapproved toolsets, and is terminated with Iris through a Windows Job
Object. It exposes Iris-owned memory query/proposal plus reviewed `read_file`,
`write_file`, `patch`, `search_files`, `terminal`, `process`, and reviewed
isolated browser tools. Ordinary
work uses the active session approval; destructive, sensitive, credential,
install/admin, and scope-expanding actions require separate confirmation. Tool
results carry source and provenance back to Iris, and memory proposals remain
staged until the user accepts them.
Pinned executable environments live under `.iris-runtime`; persistent Hermes
browser profile/download state and Hermes home state live under `.iris-data` so
installer upgrades replace binaries without erasing user state.
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
npm run test:python
scripts\test_vision_text_diagnostics.ps1
scripts\test_release_model_e2e.ps1
scripts\iris_preflight_wizard.ps1
scripts\iris_setup_wizard.ps1 -NonInteractive
scripts\test_windows_installer.ps1
scripts\test_windows_signed_installer_readiness.ps1
scripts\test_windows_msix_signature.ps1
git diff --check
```

Native ASR builds require `libclang`. Workspace pins `LIBCLANG_PATH` in `.cargo/config.toml` to local Python `libclang` package installed for this build.

Kokoro TTS uses local assets under `models/kokoro/` and the `af_heart` voice declared in `manifest.json`. The current helper requires Python with `kokoro-onnx` and `soundfile` installed.

## Run

Download and setup guide: `docs/download-and-run.md`.
Architecture notes: `docs/iris-architecture.md`.
Beginner preflight guide: `docs/installer-preflight.md`.
Windows installer plan: `docs/windows-installer.md`.
Signed installer decision: `docs/signed-installer-decision.md`.
Runtime orchestration: `docs/runtime-orchestration.md`.
Manual end-user test report: `docs/manual-end-user-test-v0.1.0.md`.
The portable release includes `Iris Setup Wizard.bat` for beginner setup and
`Check Iris Preflight.bat` for read-only diagnostics.

Console:

```powershell
cargo run -p iris-runtime -- --ask "What can you do?"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\iris_document_ocr.ps1" -ImagePath "C:\path\to\document-image.png"
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
Finish checklist: `docs/finish-checklist.md`.

Diagnostics:

- `diagnostics/manual-launch.log`
- `diagnostics/voice-events.jsonl`
- `diagnostics/voice-latency.txt`

## Public Use

This code is provided for local testing, learning, and bug-fix collaboration. Before publishing, confirm third-party model and asset licenses for anything you redistribute. Ollama model blobs, Kokoro model files, Whisper model files, and other downloaded assets may have their own license terms and should not be assumed to be covered by this repository license.

The root `package.json` remains marked `"private": true` to prevent accidental npm publication. That does not limit GitHub source access, cloning, local testing, or pull requests.
