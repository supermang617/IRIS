# Current Track

## Active milestone

Voice input to spoken Iris response.

Command:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_voice_to_spoken_turn.ps1

## Current status

Passed:

- HUD typed text response
- role handling
- foundation guard
- speech plan
- text-to-spoken Kokoro turn
- voice input boundary

Now verifying:

voice input
-> transcript
-> Iris response
-> spoken Kokoro answer

## Branch point

After this passes cleanly, this is the next conversation branch-off checkpoint.
