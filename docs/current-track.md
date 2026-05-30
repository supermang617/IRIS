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

Runtime now exposes UI scaffold status.

Useful command:

cargo run -p iris-runtime -- ui-status

## Why this is next

The v0.1 plan requires Iris-owned typed input, visible PTT state, and explicit absence language in the UI.

We are still avoiding GUI dependencies until the UI model and safety language are stable.

## Do next

Run the UI runtime status check.

Then decide whether to add the smallest real desktop HUD dependency slice.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, or wake word runtime before the HUD and visible voice-state path are stable.
