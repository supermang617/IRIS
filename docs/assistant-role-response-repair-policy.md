# Assistant Role Response Repair Policy

Status: active product rule.

## Required HUD path

HUD typed responses must use:

checked_local_response_for_hud_v4

## Rule

Iris must distinguish the user from herself in assistant responses.

User:

Iris, your voice sounds awesome.

Bad Iris response:

I'm glad your voice sounds good.

Correct Iris response:

I'm glad my voice sounds good.

## Boundary

This applies to assistant output only.

Direct user input remains untouched.

This does not add memory, screen capture, OCR, wake word runtime, input simulation, clipboard access, or system control.
