# Kokoro ONNX Voice Integration

Status: development helper scripts added.

## Production direction

Production TTS target:

Kokoro ONNX

Initial preferred voice:

af_heart

Temporary current fallback:

Windows speech synthesis

## Important boundary

Kokoro helper scripts are development setup helpers.

They may install Python packages and download model files only when explicitly run with:

scripts\setup_iris_kokoro_tts.ps1 -Install

Normal Iris runtime does not download models.

Normal Iris runtime does not use cloud TTS.

## Install

Full model:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_kokoro_tts.ps1 -Install

Smaller int8 model:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\setup_iris_kokoro_tts.ps1 -Install -UseInt8

## Speak a test sentence

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\speak_iris_kokoro.ps1 -Text "Hello, I am Iris."

## Speak a checked Iris model response with Kokoro

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_iris_kokoro_response.ps1 -Prompt "hello iris"

## Future architecture

Later, replace this Python development helper with an Iris-owned TTS abstraction and then a Rust/ONNX integration if practical.

Do not add heavy TTS architecture until the first text/voice milestone is stable.
