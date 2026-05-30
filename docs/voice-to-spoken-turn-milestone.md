# Voice To Spoken Turn Milestone

Status: active branch-off milestone.

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_voice_to_spoken_turn.ps1

## Test phrase

Testing now, Iris local voice test.

## Verified path

Voice input
-> soft transcript quality gate
-> transcript file
-> checked Iris response
-> role repair
-> natural speech rendering
-> VoiceOutputPlan
-> dev Kokoro speech boundary
-> audible Iris response

## Branch point

After this passes cleanly, branch the conversation.
