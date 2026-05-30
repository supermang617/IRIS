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

## Current architecture step

Runtime now reads voice defaults from the iris-voice crate.

Useful runtime commands:

cargo run -p iris-runtime -- self-check
cargo run -p iris-runtime -- voice-status
cargo run -p iris-runtime -- response-check-test

## Wake word requirement

Wake word is a required future feature.

Preferred wake phrase:

Iris

Do not implement wake word as default yet.

Correct order:

1. typed prompt
2. explicit one-shot voice
3. push-to-talk
4. visible listening state
5. optional local wake word while Iris is open

## Do next

Run Kokoro voice milestone verification again.

Then start push-to-talk metadata and visible listening state scaffolding.

## Do not do yet

Do not add screen capture, OCR, memory database, full UI, dashboard, always-listening voice, or wake word runtime before push-to-talk and visible voice state are stable.
