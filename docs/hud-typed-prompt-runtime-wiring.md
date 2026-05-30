# HUD Typed Prompt Runtime Wiring

Status: active HUD integration slice.

## Purpose

The HUD typed prompt field now connects to the existing checked Iris response path.

## Current path

HUD typed prompt
-> runtime responder closure
-> ContextGate
-> PromptBuilder
-> selected local model loopback
-> ResponsePostChecker
-> HUD response text

## Commands

Open HUD:

cargo run -p iris-runtime -- hud

Command-line HUD responder test:

cargo run -p iris-runtime -- hud-submit-test "hello iris"

## Current limitation

The HUD response path is synchronous.

The window may pause while the local model responds.

This is acceptable for the first wiring slice.

Next improvement is cancellation/worker-thread separation.

## Boundary

This slice does not add:

- Kokoro speech from HUD
- screen capture
- OCR
- memory database
- dashboard
- wake word runtime
- always-listening voice
- input simulation
- clipboard access
- system control
