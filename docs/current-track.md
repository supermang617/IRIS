# Current Track

## Current checkpoint

Dev-only HUD speech boundary.

Command:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_dev_hud_speech_boundary.ps1 -Prompt "Iris, your voice sounds awesome."

## Why this is next

We already proved the HUD speech plan.

Now we verify that the approved, role-repaired speech text can reach the existing Kokoro voice path without adding process execution inside the Rust runtime.

## Next after this passes

Manual voice confirmation, then decide the clean permanent TTS boundary.

## Do not do yet

Do not add runtime shell execution, screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, input simulation, clipboard access, or system control.
