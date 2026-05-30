# Iris Voice Strategy

Status: active development decision.

## Goal

Iris must have a natural, humanlike female voice for the v0.1 experience.

## Current voice backend

Current open-source local TTS development backend:

Kokoro ONNX

Default development voice:

af_heart

Temporary fallback:

Windows speech synthesis

## Why Kokoro ONNX

Kokoro ONNX is the selected near-term open-source voice path because it is:

- local
- open-source / open-weight
- lightweight enough for development
- capable of natural female voices
- simple to call from the current PowerShell workflow
- compatible with future Rust integration through ONNX Runtime / ort

## Current integration mode

For now, Kokoro runs as a development helper:

scripts/setup_iris_kokoro_onnx.ps1
scripts/speak_iris_kokoro.ps1
scripts/ask_iris_local_speak.ps1

This is not the final Rust iris-voice crate yet.

## Production target

Future production path:

iris-voice
-> Kokoro ONNX wrapper
-> checked assistant response
-> local audio generation
-> interruptible playback
-> Panic Stop cancellation

## Safety rules

TTS is output only.

TTS must not add system control.

TTS must not speak blocked model output.

TTS must stay local.

TTS must not require cloud APIs.

TTS must eventually respect Panic Stop.
