# Current Track

## Current checkpoint

Voice input transcript quality gate.

Command:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_voice_input_boundary.ps1 -ExpectedPhrase "Hello Iris."

## Why this matters

Iris should not answer bad transcripts.

If STT hears "Brewers" when the user said "Hello Iris", the transcript should fail before Iris responds.

## Next after this passes

Run the voice-to-spoken milestone again using the verified transcript.
