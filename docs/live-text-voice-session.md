# Live Text And Voice Session

Status: active manual milestone command.

## Purpose

This script runs the current user-facing voice milestone:

typed prompt
-> Iris
-> checked local model response
-> Kokoro voice

then:

explicit one-shot spoken prompt
-> Iris
-> checked local model response
-> Kokoro voice

## Command

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_iris_live_text_voice_session.ps1

## Faster command after baseline already passed

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_iris_live_text_voice_session.ps1 -SkipBuild

## Text only plus Kokoro, no microphone

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_iris_live_text_voice_session.ps1 -NoVoiceInput

## Safety boundary

This script does not add:

- wake word runtime
- always-listening mode
- screen control
- keyboard control
- mouse control
- clipboard access
- shell execution inside Iris runtime
- browser automation
- plugins

Voice input is explicit and one-shot only.
