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
- HUD typed prompt to checked response wiring

## Current product rule

Direct user input must be preserved.

Typed input must not be censored, softened, paraphrased, or profanity-filtered.

Voice input may be misrecognized by ASR, but Iris should not intentionally sanitize it.

## Current HUD command

cargo run -p iris-runtime -- hud

## Current HUD submit test

cargo run -p iris-runtime -- hud-submit-test "hello iris"

## Do next

Run the manual HUD typed prompt test.

Verify the HUD preserves typed user text and shows checked response text.

Then add Kokoro speech output from HUD only after text response is stable.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, input simulation, clipboard access, or system control.
