# Current Track

Use this file to avoid drifting from the roadmap.

## Current goal

Stabilize the first text and voice response milestone, then upgrade voice quality.

## Voice direction

Production TTS target:

Kokoro ONNX with a natural female voice.

Initial Kokoro test voice:

af_heart

Current setup status:

Kokoro helper scripts are added but installation/download is explicit and separate.

## Kokoro commands

Dry-run setup:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_kokoro_tts.ps1 -DryRun

Install full Kokoro model:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_kokoro_tts.ps1 -Install

Install smaller int8 Kokoro model:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_kokoro_tts.ps1 -Install -UseInt8

Speak text with Kokoro:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\speak_iris_kokoro.ps1 -Text "Hello, I am Iris."

Speak checked Iris response with Kokoro:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_kokoro_response.ps1 -Prompt "hello iris"

## Backend direction

Long-term production LLM backend:

llama.cpp / GGUF

Current development bridge:

Ollama loopback at 127.0.0.1:11434

Ollama is not the final production dependency.

## Do next

Run Kokoro setup install when ready.

Then compare Kokoro af_heart against Windows voice output.

## Do not do yet

Do not add screen capture, OCR, memory database, full UI, dashboard, always-listening voice, or full Rust Kokoro integration before the text/voice milestone and Kokoro helper are stable.
