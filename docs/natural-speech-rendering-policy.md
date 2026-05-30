# Natural Speech Rendering Policy

Status: active speech-output rule.

## Purpose

Display text may keep symbols.

Speech text should render common symbols as natural spoken language.

## Rules

- `$25` becomes `25 dollars`
- `$25.50` becomes `25.50 dollars`
- `@` becomes `at`
- `#4` becomes `number 4`
- `#topic` becomes `hashtag topic`
- `&` becomes `and`
- parentheses become light pauses, not the word `parenthesis`
- repeated literal asterisks become counted asterisks

## Boundary

This applies to assistant speech text.

It does not change direct user input.

It does not add runtime shell execution, screen capture, OCR, memory, wake word runtime, input simulation, clipboard access, or system control.
