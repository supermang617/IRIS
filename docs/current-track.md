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

## Current HUD submit test

cargo run -p iris-runtime -- hud-submit-test "hello iris"

## Current HUD path

HUD typed prompt
-> runtime responder
-> ContextGate
-> PromptBuilder
-> selected local model loopback
-> ResponsePostChecker
-> HUD response text

## Do next

Test the HUD typed prompt path manually.

Then add Kokoro speech output from HUD only after text response is stable.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, input simulation, clipboard access, or system control.
