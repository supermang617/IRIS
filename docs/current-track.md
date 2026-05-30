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
- Iris addressee intent policy

## Current product rules

Direct user input must be preserved.

Assistant output must not speak censor asterisks for common profanity patterns.

When the user says "you" or "Iris", Iris should understand the user is speaking to Iris.

## Current HUD command

cargo run -p iris-runtime -- hud

## Current addressee test

cargo run -p iris-runtime -- addressee-intent-test

## Do next

Retest the HUD with:

Awesome, you passed our test, Iris. I am proud of you.

Expected behavior:

Iris responds as the recipient of the praise, not as if the user is praising themself.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, input simulation, clipboard access, or system control.
