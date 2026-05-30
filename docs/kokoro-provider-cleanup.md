# Kokoro Provider Cleanup

Status: active.

Kokoro validation is now split into clean layers.

## Canonical scripts

- scripts\discover_iris_kokoro_provider.ps1
- scripts\setup_iris_kokoro_tts.ps1
- scripts\speak_iris_kokoro.ps1
- scripts\validate_iris_kokoro_direct_voice.ps1

## Legacy archived scripts

Old scripts that mixed model response, ask-local routing, and Kokoro validation are archived under:

scripts\legacy\kokoro

## Rule

Do not validate Kokoro through old model-response milestone scripts.

Validate the layers separately:

1. model response
2. text conversation loop
3. direct TTS provider
4. combined voice conversation loop

This keeps voice providers swappable and prevents old route failures from being mistaken for Kokoro failures.
