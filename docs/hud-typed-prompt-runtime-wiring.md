# HUD Typed Prompt Runtime Wiring

Status: active HUD integration slice.

## Current fix

The HUD typed prompt wiring had two Rust issues:

1. A malformed `println!` string used nested unescaped quotes.
2. `LoopbackInferenceError` was formatted with Display instead of Debug.

Both are fixed.

## Current path

HUD typed prompt
-> runtime responder closure
-> ContextGate
-> PromptBuilder
-> selected local model loopback
-> ResponsePostChecker
-> HUD response text

## Commands

Command-line HUD responder test:

cargo run -p iris-runtime -- hud-submit-test "hello iris"

Open HUD:

cargo run -p iris-runtime -- hud

## Rule

Do not add Kokoro speech from HUD until the typed text response path is stable.
