# Current Track

Use this file to avoid drifting from the roadmap.

## Current goal

Reach the first basic text and voice response milestone without weakening the safety boundary.

## Current status

Iris can already be tested by text through local model loopback when the selected Ollama model is installed.

Useful commands:

cargo run -p iris-runtime -- self-check
cargo run -p iris-runtime -- model-plan
cargo run -p iris-runtime -- prompt-preview "hello iris"
cargo run -p iris-runtime -- ask-local "hello iris"
cargo run -p iris-runtime -- chat-local
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_ollama_loopback.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\ask_iris_local.ps1 "hello iris"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\chat_iris_local.ps1

## Do next

Panic Stop skeleton.

Reason:

Panic Stop must exist before adding more voice and speech behavior.

## Do not do yet

Do not add screen capture, OCR, memory database, full UI, dashboard, or always-listening voice before the basic text/voice milestone is stable.
