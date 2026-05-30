# Push-To-Talk Runtime Status

Status: active scaffold.

## Purpose

Runtime must expose the push-to-talk visible-state model before real push-to-talk capture is added.

## Runtime commands

Voice status:

cargo run -p iris-runtime -- voice-status

Push-to-talk state test:

cargo run -p iris-runtime -- voice-ptt-state-test

## Expected state sequence

Idle
-> Armed
-> Recording
-> ProcessingTranscript
-> Speaking
-> Idle

Panic Stop sequence:

Recording
-> Stopped

## Safety boundary

This scaffold does not add:

- global hotkeys
- audio capture dependencies
- ASR dependencies
- wake word runtime
- always-listening mode
- input simulation
- clipboard access
- shell execution

## Rule

Only `Recording` means the microphone is active.

Every non-idle state must be visible to the user in the future UI.
