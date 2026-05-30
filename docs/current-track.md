# Current Track

Use this file to avoid drifting from the roadmap.

## Current milestone

Iris has reached:

- local model response
- response post-check
- Kokoro ONNX voice output
- default voice: af_heart
- default speed: 0.95
- explicit one-shot voice input helper
- typed prompt helper
- Panic Stop skeleton
- runtime voice-status
- runtime push-to-talk visible-state test
- iris-ui scaffold

## Current architecture step

Runtime exposes UI scaffold status.

Useful command:

cargo run -p iris-runtime -- ui-status

## Current diagnostics command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\diagnose_iris_current_milestone.ps1

## Why this is next

The v0.1 plan requires Iris-owned typed input, visible PTT state, explicit absence language, and repeatable audit tooling before real GUI dependencies.

## Do next

Run the diagnostics command.

Then decide whether to add the smallest real desktop HUD dependency slice.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, or wake word runtime before the HUD and visible voice-state path are stable.
