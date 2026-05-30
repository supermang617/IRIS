# Current Track

## Current product rule

Iris must distinguish user/Iris roles across both prompt interpretation and assistant response repair.

Current commands:

cargo run -p iris-runtime -- assistant-role-repair-test
cargo run -p iris-runtime -- deictic-role-test

Manual HUD retest:

cargo run -p iris-runtime -- hud

Test prompt:

Iris, your voice sounds awesome.

Expected:

Iris says "my voice", not "your voice".

## Do next

Retest HUD role handling.

Then add HUD Kokoro speech only after role handling remains stable.
