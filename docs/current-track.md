# Current Track

Use this file to avoid drifting from the roadmap.

## Current product rule

Iris must resolve direct conversation roles correctly:

- I/me/my = user
- you/your/Iris = Iris
- we/us/our = user and Iris together unless context says otherwise

## Current test commands

cargo run -p iris-runtime -- deictic-role-test

cargo run -p iris-runtime -- hud-submit-test "Okay that was the test. You passed! Congrats!!!"

## Manual HUD retest

cargo run -p iris-runtime -- hud

Test prompt:

Okay that was the test. You passed! Congrats!!!

Expected behavior:

Iris responds as the one who passed.

Bad behavior:

Iris says the user passed.

## Do next

Retest the HUD.

Then add HUD Kokoro speech only after text role interpretation is stable.
