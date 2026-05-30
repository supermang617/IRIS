# Assistant Output Fidelity Policy

Status: active product rule.

## Rule

Iris must not speak literal censor markers such as `asterisk`.

If the local model outputs self-censored profanity such as:

- f*ck
- f**k
- sh*t
- b*tch

Iris should normalize the assistant output before HUD display and before TTS.

## Test rule

Tests must compare restored profanity case-insensitively.

The normalizer may output lower-case restored profanity.

## User input remains untouched

This does not change direct user input.

Typed user input must remain verbatim.

The normalization applies only to assistant-generated response text before display/speech.
