# Current Track

## Current checkpoint

Iris now uses a foundation guard before moving to the next feature slice.

Command:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_foundation_guard.ps1

## Working rule

Prefer clean canonical rewrites over stacked patch chains when a file becomes unstable.

No suffixed helper chains for HUD behavior.

Canonical HUD function:

checked_local_response_for_hud

## Next feature after this passes

Add HUD Kokoro speech output.

Only after:

- foundation guard passes
- HUD role handling remains stable
- user input is preserved
- assistant output has no censor-marker asterisks
- diagnostics remain clean

## Do not do yet

Do not add screen capture, OCR, memory database, full dashboard, always-listening voice, wake word runtime, input simulation, clipboard access, or system control.
