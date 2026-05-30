# Current Track

Use this file to avoid drifting from the roadmap.

## Current goal

Validate and harden the first basic text and voice response milestone.

## Voice direction

Current open-source local TTS backend:

Kokoro ONNX

Current default voice:

af_heart

Temporary fallback:

Windows speech synthesis

## Useful voice commands

Setup Kokoro:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_kokoro_onnx.ps1

Test Kokoro voice only:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\speak_iris_kokoro.ps1 -Text "Hello, I am Iris."

Text prompt to Kokoro spoken response:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_text_voice_response.ps1 -Prompt "hello iris"

Windows fallback:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_text_voice_response.ps1 -Prompt "hello iris" -TtsBackend Windows

## Do next

Run Kokoro setup and hear the first Kokoro Iris voice.

Then run the text prompt to Kokoro spoken response test.

## Do not do yet

Do not add screen capture, OCR, memory database, full UI, dashboard, always-listening voice, or full Rust Kokoro integration before the basic text/voice milestone is stable.
