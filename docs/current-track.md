# Current Track

Use this file to avoid drifting from the roadmap.

## Current goal

Validate and harden the first basic text and voice response milestone.

## Current status

Iris supports:

- typed prompt through ask-local
- explicit one-shot voice input helper
- local model response through Ollama loopback
- response post-check before displaying or speaking output
- local spoken response through Windows speech synthesis
- Panic Stop skeleton
- safety spine verification

Useful commands:

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

If milestone verification passes cleanly, improve voice reliability and cancellation boundaries.

If it fails, fix the smallest failing helper first.

## Do not do yet

Do not add screen capture, OCR, memory database, full UI, dashboard, or always-listening voice before the basic text/voice milestone is stable.
