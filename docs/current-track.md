# Current Track

Use this file to avoid drifting from the roadmap.

## Current milestone

Iris has reached:

- local model response
- response post-check
- Kokoro ONNX voice output
- explicit one-shot voice input helper
- typed prompt helper
- Panic Stop skeleton
- runtime voice-status
- runtime push-to-talk visible-state test
- iris-ui scaffold
- runtime ui-status
- clean milestone diagnostics script
- first minimal desktop HUD slice

## Current HUD command

cargo run -p iris-runtime -- hud

## Current HUD scope

The first HUD slice shows:

- safety absence language
- typed prompt input
- response display area
- visible voice state

Typed prompt capture is local to the HUD model for now.

## Do next

Wire HUD typed prompt submission to the existing checked Iris text response path.

Then wire checked response text into Kokoro TTS only after the text path is stable.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, input simulation, clipboard access, or system control.
