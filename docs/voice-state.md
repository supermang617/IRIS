# Iris Voice State

Status: scaffolding.

## Purpose

The voice state model exists so Iris can show clear user-visible status before adding real push-to-talk and wake-word behavior.

## Current states

- Idle
- Armed
- Listening
- Transcribing
- Thinking
- Speaking
- Stopped

## Current rules

Voice capture must be visible to the user.

Voice capture must be bounded.

Transcripts must enter ContextGate.

Blocked responses must not be spoken.

Panic Stop must move voice state to Stopped.

## Current safe activation modes

- TypedPrompt
- OneShotVoice
- PushToTalk

## Future activation mode

- FutureWakeWordDisabledByDefault

Wake word remains required later, but it is not enabled by default at this stage.

## Current Kokoro defaults

- backend: Kokoro ONNX
- voice: af_heart
- speed: 0.95
- wake signal: 900 ms
- lead silence: 300 ms
- tail silence: 300 ms
