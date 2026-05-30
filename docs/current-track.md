# Current Track

Use this file to avoid drifting from the roadmap.

## Current goal

Validate and harden the first basic text and voice response milestone.

## Backend direction

Long-term production backend:

llama.cpp / GGUF

Current development bridge:

Ollama loopback at 127.0.0.1:11434

Ollama is only being used to test local model behavior quickly on Windows.

Do not make Ollama a required production dependency.

## Voice direction

Long-term production TTS target:

Kokoro ONNX

Current development speech output:

Windows local speech synthesis helper

Windows SAPI is temporary and only used to test the text-to-speech pipeline.

Iris v0.1 should use a natural female Kokoro ONNX voice if packaging and quality tests pass.

Fallback candidate:

Piper

Do not add heavy voice cloning or large Python-first TTS stacks before the text/voice milestone is stable.

## Current status

Iris supports:

- typed prompt through ask-local
- explicit one-shot voice input helper
- local model response through Ollama loopback
- response post-check before displaying or speaking output
- local spoken response through Windows speech synthesis
- Panic Stop skeleton
- safety spine verification

## Useful commands

cargo run -p iris-runtime -- self-check
cargo run -p iris-runtime -- panic-stop-test
cargo run -p iris-runtime -- response-check-test
cargo run -p iris-runtime -- model-plan
cargo run -p iris-runtime -- prompt-preview "hello iris"
cargo run -p iris-runtime -- ask-local "hello iris"
cargo run -p iris-runtime -- chat-local
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_text_voice_response.ps1 "hello iris"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_voice_text_response.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_text_voice_milestone.ps1

## Do next

Rerun the live text and voice milestone test.

Then start a small iris-voice abstraction only after the milestone is stable.

## Do not do yet

Do not add screen capture, OCR, memory database, full UI, dashboard, always-listening voice, or full Kokoro integration before the basic text/voice milestone is stable.
