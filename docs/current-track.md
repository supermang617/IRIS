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

## Current fix

PowerShell native command capture is now handled with Start-Process, redirected stdout, and redirected stderr.

Avoid:
- `2>&1` with Cargo
- direct `& cargo ...` capture when stderr matters
- ProcessStartInfo.ArgumentList because it is not reliable across Windows PowerShell versions

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

Rerun milestone verification.

Then run the live voice input test manually.

## Do not do yet

Do not add screen capture, OCR, memory database, full UI, dashboard, or always-listening voice before the basic text/voice milestone is stable.
