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

Kokoro ONNX with a natural female voice.

Current development speech output:

Windows local speech synthesis helper with selectable installed voice.

Use this to test voice preference now without adding heavy architecture.

## Useful commands

List installed Windows voices:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\list_iris_windows_voices.ps1

Text to selected voice:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_text_voice_response.ps1 -Prompt "hello iris" -VoiceName "VOICE NAME HERE"

Voice input to selected voice:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_voice_text_response.ps1 -TimeoutSeconds 8 -VoiceName "VOICE NAME HERE"

Other commands:

cargo run -p iris-runtime -- self-check
cargo run -p iris-runtime -- panic-stop-test
cargo run -p iris-runtime -- response-check-test
cargo run -p iris-runtime -- model-plan
cargo run -p iris-runtime -- prompt-preview "hello iris"
cargo run -p iris-runtime -- ask-local "hello iris"
cargo run -p iris-runtime -- chat-local
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify_iris_text_voice_milestone.ps1

## Do next

List installed Windows voices and pick the best current female voice for temporary development testing.

Then continue toward the iris-voice abstraction and Kokoro ONNX later.

## Do not do yet

Do not add screen capture, OCR, memory database, full UI, dashboard, always-listening voice, or full Kokoro integration before the basic text/voice milestone is stable.
