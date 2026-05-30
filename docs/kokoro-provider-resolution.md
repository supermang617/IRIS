# Kokoro Provider Resolution

Status: recovery verified.

Qwen is the reasoning model. Kokoro is the preferred local TTS provider. SAPI remains the Windows fallback.

Selected model:

C:\Projects\IRIS\.iris-dev\tts\kokoro\kokoro-v1.0.onnx

Selected voice/config asset:

C:\Projects\IRIS\.iris-dev\tts\kokoro\voices-v1.0.bin

Next validation command:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate_iris_kokoro_direct_voice.ps1

