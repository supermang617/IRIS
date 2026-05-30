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

## Current UI architecture

Active path:

- Rust-native HUD
- egui
- eframe

Do not switch to Tauri right now.

## Future UI polish note

Native material/backdrop effects are desirable later.

Preferred Windows target:

Mica

Reason:

- subtle Windows 11 look
- low overhead
- good thermal-safe fit

Do not add Mica, Acrylic, Tauri, window-vibrancy, or transparent-window work yet.

## Current next implementation target

Wire HUD typed prompt submission to the existing checked Iris text response path.

Then wire checked response text into Kokoro TTS after the text path is stable.

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, Tauri, native material effects, input simulation, clipboard access, or system control.
