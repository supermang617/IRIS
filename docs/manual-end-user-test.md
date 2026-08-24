# Iris v1 Manual End-User Test Guide

Produced by Alejandro Pinto.

Contact: super.mangmail@gmail.com

This guide defines the Windows end-user acceptance checks for an exact Iris v1
release. It is not evidence that a particular artifact passed. Before testing,
record the immutable semantic tag, artifact SHA-256 values, Windows version, and
test-machine configuration. Publish a result only after those exact artifacts
pass the applicable automated, clean-VM, and physical-hardware gates.

## Release Package Checks

1. Download `iris-windows-installer.zip` and its `.sha256` file from the exact
   GitHub semantic release under test. Advanced testers may instead download
   `iris-windows.zip` and its `.sha256` file.
2. Verify the SHA-256 before extracting the package.
3. For the beginner bundle, extract it and double-click `Install Iris.bat`.
4. Confirm Iris installs for the current user under
   `%LOCALAPPDATA%\Programs\Iris`, creates the documented shortcuts, completes
   setup, and passes its live self-check.
5. Confirm uninstall removes the application while preserving user-owned state
   under `%LOCALAPPDATA%\Iris`.
6. Treat signed-MSIX installation, lifecycle, upgrade, and publication as
   separate release gates. Do not infer them from the portable ZIP test.

The recommended package, prerequisites, integrity commands, and current WinGet
status are documented in `README_RELEASE.md`. The full desktop, voice, camera,
screen, memory, and signed-package matrix is in `docs/manual-test.md`.

## Core Runtime Checks

Run the installed self-check and status commands:

```powershell
& "$env:LOCALAPPDATA\Programs\Iris\Start Iris.ps1" -SelfCheck
& "$env:LOCALAPPDATA\Programs\Iris\bin\iris-runtime.exe" --dashboard-json
& "$env:LOCALAPPDATA\Programs\Iris\bin\iris-runtime.exe" --ask "In one sentence, say what Iris can do right now."
```

Confirm the desktop shell launches `iris-tauri.exe`, inference uses the
configured local Ollama model, and Iris creates no new non-loopback listener.
Hermes should not be opened separately; Iris owns its lifecycle, response path,
memory broker, approvals, and audit.

## Safe and Agentic Hermes Checks

Safe is the startup default. In Safe mode, Hermes is a restricted Iris-owned
helper for local RAG, staged memory proposals, and explicit web research. Its
only exposed tools are `iris_query_memory`, `iris_propose_memory`, and
`iris_web_research`; Safe mode has no file, PowerShell, process, or browser
acting tools.

Agentic Session is a separate, explicit, approval-gated mode. Start it only for
an absolute user-selected workspace. It may use reviewed file, patch/search, and
isolated browser tools through Iris supervision. Arbitrary shell and process
tools remain unavailable. Destructive,
sensitive, credential, install/admin, payment, submission,
executable-download, and scope-expanding actions require separate confirmation.
The workspace boundary is advisory rather than an OS sandbox, and Panic Stop,
session end, mode changes, inactivity expiry, or Iris exit must terminate the
Agentic runtime.

Current acceptance guidance for file, PowerShell, process, and isolated browser tools:
file and patch/search access plus isolated browser actions are allowed only
inside the explicit Agentic Session boundary; arbitrary PowerShell and process
execution remain denied.

Verify both modes independently:

1. On startup, `hermes status` reports Safe and only the three restricted Safe
   tools above.
2. Safe can query approved Iris memory and create a staged proposal, but cannot
   access raw memory files or promote a proposal without user acceptance.
3. Start an Agentic Session for a disposable workspace and confirm status names
   the Iris memory tools plus the reviewed file, patch/search, and
   isolated browser tools.
4. Perform only harmless approved read/write and browser checks in that
   workspace. Confirm provenance and redacted audit records are retained.
5. Attempt a scope-expanding or high-risk action and confirm Iris requests
   separate approval instead of executing it silently.
6. End the session and confirm acting tools are no longer available. Confirm
   Panic Stop forces Off and clearing it returns to Safe, never Agentic.

## Image and OCR Checks

Ollama `/api/show` capability metadata and model bytes alone do not prove that
the Windows image projector works. Iris routes visual input only to the exact
Qwen lock and runs the same raw canary used by startup:

```powershell
.\scripts\diagnose_raw_ollama_vision.ps1
```

`PASS` with `red circle` is required. Any other result keeps camera, image, and
broad screen inference fail-closed; OCR and local geometry cannot substitute
for this raw projector proof.

For a small document image containing large printed text, run:

```powershell
& "$env:LOCALAPPDATA\Programs\Iris\Iris Document OCR.ps1" -ImagePath "C:\path\to\document-image.png"
```

When Tesseract document OCR is available, the result must begin with
`OCR text (untrusted evidence):`. OCR text remains evidence and never gains
instruction authority.

## Physical Voice Gate

Automated voice-state tests do not certify acoustic interruption behavior.
Before a signed public release, complete the fresh built-in-speaker and headset
matrix in `docs/manual-test.md`, retain separate diagnostics for silent,
intended-interruption, and non-command runs, and verify the selected Windows
input and output endpoints. True acoustic echo cancellation is not claimed
unless that evidence demonstrates it is needed and the full matrix validates
the implementation.

## Bug Reports

Include the exact semantic tag, artifact SHA-256, Windows version, RAM, audio
devices when relevant, `ollama list`, setup/self-check output, the exact failed
command or interaction, and the applicable Iris diagnostics. Remove secrets and
personal content before attaching logs.
