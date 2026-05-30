# Current Track

## Current milestone

Text prompt to spoken Iris response.

Command:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_text_to_spoken_turn.ps1

## Current status

HUD text path works.

Role handling works.

Speech plan works.

Dev Kokoro speech boundary works.

Text-to-spoken turn is now the active milestone gate.

## Next after this passes

Build the voice-input-to-spoken-response turn:

voice input
-> transcript
-> checked HUD response path
-> Kokoro spoken response

## Do not do yet

Do not add runtime shell execution, screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, input simulation, clipboard access, or system control.
