# Voice Input Boundary

Status: active checkpoint.

## Purpose

This verifies that Iris can capture a spoken user prompt as transcript text before chaining it into the response and Kokoro speech path.

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_voice_input_boundary.ps1 -ExpectedPhrase "Hello Iris."

## Rule

Iris must not continue when the transcript is clearly wrong.

If the user is asked to say:

Hello Iris.

and the transcript becomes something unrelated like:

Brewers

the script must fail and write:

.iris-dev\voice\last-transcript-rejected.txt

## Reason

A bad transcript is not an Iris reasoning failure.

It is a speech-to-text capture failure.

The response path should not run until the transcript passes the quality gate.

## Next after this passes

Voice input
-> verified transcript
-> checked HUD response path
-> VoiceOutputPlan
-> Kokoro spoken answer
