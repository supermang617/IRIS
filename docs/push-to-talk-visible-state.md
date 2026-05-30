# Push-To-Talk And Visible Voice State

Status: architecture scaffold.

## Purpose

This document tracks the safe voice-input path before wake word.

## Current rule

Voice input must be explicit.

Current accepted activation modes:

- typed prompt
- one-shot voice helper
- future push-to-talk

Wake word is required later, but it must wait until push-to-talk and visible listening state are stable.

## Push-to-talk state model

The `iris-voice` crate now defines:

- Idle
- Armed
- Recording
- ProcessingTranscript
- Speaking
- Stopped

Only `Recording` means the microphone is active.

Every non-idle state requires a visible status in the future UI.

## Safety boundary

This scaffold does not add:

- global hotkeys
- background listening
- wake word runtime
- ASR dependencies
- audio capture dependencies
- input simulation
- clipboard access
- shell execution

## Next route

1. Wire this state into runtime `voice-status`.
2. Add a small visible-state CLI test.
3. Keep PowerShell one-shot voice helper as the temporary microphone path.
4. Add real push-to-talk only after the UI/listening indicator exists.
