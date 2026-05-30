# Current Track

## Active milestone

Voice input to spoken Iris response.

Command:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_voice_to_spoken_turn.ps1

## Branch point

After this passes cleanly, create the next conversation handoff.

## Current verified stack

- HUD typed response
- role handling
- profanity marker normalization
- natural speech rendering
- foundation guard
- Kokoro dev speech boundary
- typed prompt to spoken response
- voice input soft quality gate

## Current target

spoken prompt
-> transcript
-> Iris response
-> spoken Kokoro answer
