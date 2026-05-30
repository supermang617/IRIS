# Assistant Role Response Repair Policy

Status: active product rule.

## Required runtime path

HUD typed responses must use one clean function:

checked_local_response_for_hud

Do not create parallel helper chains such as `_v3`, `_v4`, or future suffixed variants.

## Rule

Iris must distinguish the user from herself in assistant responses.

User:

Iris, your voice sounds awesome.

Bad Iris response:

I'm glad your voice sounds good.

Correct Iris response:

I'm glad my voice sounds good.

User:

You passed.

Bad Iris response:

I'm glad you passed.

Correct Iris response:

I'm glad I passed.

## Boundary

This applies to assistant output only.

Direct user input remains untouched.

This does not add memory, screen capture, OCR, wake word runtime, input simulation, clipboard access, or system control.
