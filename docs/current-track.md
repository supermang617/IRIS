# Current Track

## Current checkpoint

Natural speech rendering.

Command:

cargo run -p iris-runtime -- natural-speech-rendering-test

## Why this matters

Before full back-and-forth voice, Iris speech must avoid robotic symbol reading.

Speech text should sound natural while display text can remain exact.

## Next after this passes

Continue voice-input-to-spoken-response wiring:

voice input
-> transcript
-> checked response
-> natural speech rendering
-> Kokoro spoken answer
