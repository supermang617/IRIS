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
- user input fidelity policy
- assistant output anti-asterisk normalization

## Current product rules

Direct user input must be preserved.

Assistant output must not speak censor asterisks for common profanity patterns.

## Current HUD command

cargo run -p iris-runtime -- hud

## Current HUD submit test

cargo run -p iris-runtime -- hud-submit-test "hello iris"

## Current output normalization test

cargo run -p iris-runtime -- assistant-text-normalization-test

## Do next

Run the manual HUD typed prompt test again.

Verify:
- user typed text is preserved
- assistant response does not show f*ckin-style censor markers for common profanity
- response still passes ResponsePostChecker

Then add Kokoro speech output from HUD only after text response is stable.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, input simulation, clipboard access, or system control.
