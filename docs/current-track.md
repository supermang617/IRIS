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

## Current architecture step

Add the smallest `iris-ui` scaffold without GUI dependencies.

This creates the HUD-facing state model for:

- typed prompt
- response lines
- safety absence language
- visible voice status

## Why this is next

The v0.1 plan requires Iris-owned typed input, visible PTT state, and explicit absence language in UI.

We are not adding `egui/winit` yet.

## Do next

Wire `iris-ui` into runtime status.

Then decide when to add actual GUI dependencies.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, or GUI dependencies before this scaffold is stable.
