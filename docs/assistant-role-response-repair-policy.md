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

## Implementation rule

HUD responses must use the checked v3 HUD response path.

The v3 path applies:

1. deterministic Iris-directed reply handling
2. assistant profanity marker normalization
3. assistant user/Iris role repair
4. ResponsePostChecker

## Boundary

This applies to assistant output only.

Direct user input remains untouched.

This does not add memory, screen capture, OCR, wake word runtime, input simulation, clipboard access, or system control.
