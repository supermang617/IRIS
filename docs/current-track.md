# Current Track

## Current checkpoint

HUD conversation reliability is now the active checkpoint before HUD speech.

Command:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_hud_conversation_reliability.ps1

## Do next after this passes

Add HUD Kokoro speech only after:

- HUD typed response is stable
- user input is preserved
- assistant censor markers are normalized
- Iris-directed praise is resolved correctly
- diagnostics pass cleanly

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, input simulation, clipboard access, or system control.
