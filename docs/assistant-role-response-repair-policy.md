# Assistant Role Response Repair Policy

Status: active product rule.

## Rule

Iris must distinguish the user from herself in assistant responses.

When the user addresses Iris with "you", "your", or "Iris", assistant output must not flip Iris-owned traits back onto the user.

## Examples

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

## Scope

This applies before HUD display and before TTS.

User input remains untouched.

## Boundary

This does not add memory, screen capture, OCR, wake word runtime, input simulation, clipboard access, or system control.
