# HUD Dependency Readiness

Status: decision checkpoint.

## Current state

Iris currently has:

- local model response
- response post-check
- Kokoro ONNX spoken output
- explicit one-shot voice input helper
- push-to-talk visible-state scaffold
- `iris-ui` HUD state scaffold
- runtime `ui-status`
- current milestone diagnostics script

## Why this checkpoint exists

The next real product step is the minimal desktop HUD.

The v0.1 plan requires Iris-owned typed input, visible push-to-talk state, safety status, and eventually a lightweight desktop UI.

The planned GUI direction is:

- winit
- egui

Adding those crates is a dependency change, so it should be explicitly approved before implementation.

## Readiness command

Run:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_hud_readiness.ps1

## What must pass before GUI work

- cargo fmt
- cargo build
- cargo test
- xtask audit
- runtime self-check
- runtime ui-status
- runtime voice-status
- runtime push-to-talk visible-state test
- runtime response post-check test
- current milestone diagnostics

## Approved next implementation after user approval

Smallest desktop HUD slice:

- create a real window
- show Iris safety absence language
- show typed prompt box
- show Send button
- show response text area
- show visible voice state label
- no screen capture
- no OCR
- no memory database
- no wake word
- no system control
- no clipboard
- no input simulation

## Not approved yet

Do not add GUI dependencies until the user explicitly approves.

Do not add full dashboard yet.
