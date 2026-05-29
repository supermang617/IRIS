# Current Track

Use this file to avoid drifting from the roadmap.

## Current goal

Reach the first basic text and voice response milestone without weakening the safety boundary.

## Current status

Iris can already be tested by text through local model loopback when the selected Ollama model is installed.

Panic Stop skeleton is implemented as a tested runtime-safe flag.

Response post-check is implemented and blocks unsafe assistant capability claims.

Text prompt to spoken local response helper is hardened and requires Response post-check: PASS before speaking.

One-shot explicit voice input helper is scaffolded through local Windows speech recognition.

Useful commands:

cargo run -p iris-runtime -- self-check
cargo run -p iris-runtime -- panic-stop-test
cargo run -p iris-runtime -- response-check-test
cargo run -p iris-runtime -- model-plan
cargo run -p iris-runtime -- prompt-preview "hello iris"
cargo run -p iris-runtime -- ask-local "hello iris"
cargo run -p iris-runtime -- chat-local
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_ollama_loopback.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ask_iris_local.ps1 "hello iris"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\chat_iris_local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_text_voice_response.ps1 "hello iris"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_voice_text_response.ps1

## Do next

Run the first explicit voice input plus spoken response test.

Reason:

This is the first basic voice milestone checkpoint.

## Do not do yet

Do not add screen capture, OCR, memory database, full UI, dashboard, or always-listening voice before the basic text/voice milestone is stable.
