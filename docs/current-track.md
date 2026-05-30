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
- runtime ui-status
- clean milestone diagnostics script

## Current checkpoint

HUD dependency readiness gate.

Command:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_hud_readiness.ps1

## Next decision

Approve or reject adding the minimal GUI dependencies:

- winit
- egui

## If approved

Build the smallest real desktop HUD slice:

- window
- safety absence language
- typed prompt field
- response area
- visible voice state label
- no dashboard yet

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, or GUI dependencies before explicit approval.
