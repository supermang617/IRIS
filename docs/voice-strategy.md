# Iris Voice Strategy

Status: design decision, not full implementation yet.

## Goal

Iris must have a natural, humanlike female voice for the v0.1 experience.

The voice should feel warm, clear, calm, and personal without adding large architectural overhead.

## Current development state

Current speech output uses Windows local speech synthesis only as a temporary development helper.

This is acceptable for testing the pipeline:

typed/voice input
-> ContextGate
-> PromptBuilder
-> local model
-> ResponsePostChecker
-> text output
-> spoken output

Windows SAPI is not the final Iris voice.

## Primary open-source target

Primary TTS target:

Kokoro ONNX

Reason:

- local-first
- open-weight model
- small enough for practical desktop use
- good naturalness for the footprint
- supports multiple voices
- has female voice options
- ONNX path fits the future Rust architecture through ort
- better fit than a large Python voice stack for v0.1

Likely initial Iris voice profile:

- natural female voice
- English first
- calm assistant tone
- medium speed
- interruptible playback
- text-only fallback available

## Secondary fallback candidate

Fallback TTS candidate:

Piper

Reason:

- fast
- local
- lightweight
- proven offline TTS path

Use Piper only if Kokoro ONNX packaging, quality, or runtime integration becomes a blocker.

## Not preferred for v0.1

Avoid heavy voice cloning or large Python-first TTS stacks for the first MVP.

Avoid making Coqui/XTTS-style cloning the default path in v0.1.

Reason:

- higher dependency weight
- more packaging friction
- more GPU/CPU overhead
- greater complexity around voice identity and consent
- not needed for the first stable Iris voice

## Architecture target

Future production path:

iris-voice
-> Kokoro ONNX runtime wrapper
-> checked assistant response
-> local audio generation
-> interruptible playback
-> Panic Stop cancellation

## Safety and privacy rules

TTS is output only.

TTS must never create a system-control path.

TTS must not require cloud APIs.

TTS must not send text to a remote service.

TTS must not speak blocked model output.

TTS must respect Panic Stop.

TTS must have a user setting for text-only mode.

## Implementation order

Do not implement full Kokoro yet.

First complete:

1. text and voice milestone stability
2. Panic Stop cancellation boundary
3. response post-check stability
4. local TTS abstraction crate
5. Kokoro ONNX prototype
6. female voice selection test
7. interruptible playback test
8. replace Windows SAPI helper with Iris-owned TTS path

## Open-source packaging target

For v0.1, Iris should eventually ship or guide install of the chosen voice model files inside Iris-owned directories.

No hidden downloads during normal runtime.

No cloud voice providers.

No paid voice APIs.
