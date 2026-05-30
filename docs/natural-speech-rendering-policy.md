# Natural Speech Rendering Policy

Status: active speech-output rule.

## Purpose

Iris should sound natural when speaking text aloud.

Display text may keep symbols.

Speech text should render common symbols as natural spoken language.

## Current rendering rules

- `$25` becomes `25 dollars`
- `$` becomes `dollars`
- `@` becomes `at`
- `#4` becomes `number 4`
- `#topic` becomes `hashtag topic`
- `&` becomes `and`
- parentheses become light pauses, not the words "parenthesis"
- repeated asterisks become a counted phrase, such as `3 asterisks`

## Important distinction

Self-censored assistant profanity like `f*ck` is normalized before speech rendering.

Literal repeated asterisks are allowed to be spoken as asterisks when they are actually the content.

## Boundary

This applies to assistant speech text.

It does not change direct user input.

It does not add screen capture, OCR, memory, wake word runtime, input simulation, clipboard access, shell execution, or system control.
