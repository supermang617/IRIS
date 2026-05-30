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

## Current architecture step

iris-voice now owns:

- voice backend metadata
- checked-response speech permission
- one-shot voice policy
- push-to-talk policy
- future wake-word disabled policy
- visible voice session state
- bounded capture metadata
- Panic Stop stopped-state metadata

## Do next

Wire the voice session state into runtime diagnostics.

Then scaffold push-to-talk as a visible state transition before adding real hotkey/audio capture.

## Do not do yet

Do not add screen capture, OCR, memory database, full UI, dashboard, always-listening voice, or wake word runtime before push-to-talk and visible voice state are stable.
