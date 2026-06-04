## Known Limitations

This repository is a Windows-only v0.1 prototype.

- Text inference requires Ollama running locally with `huihui_ai/gemma-4-abliterated:e2b` already available.
- No model downloader.
- No fallback models.
- No model auto-selection.
- No multi-model debate.
- Voice input requires the local Whisper model at `models/whisper/ggml-tiny.en.bin`.
- Spoken output requires local Kokoro assets at `models/kokoro/kokoro-v1.0.onnx` and `models/kokoro/voices-v1.0.bin`.
- Spoken output currently uses the Python `kokoro-onnx` helper with the `af_heart` voice.
- The configured Ollama model is vision-capable, but image/screen/video/document handling must remain explicit user-driven evidence.
- Native Whisper ASR and Kokoro TTS are present.
- Local memory exists, but active-memory promotion is intentionally bounded.
- Hermes integration is restricted, text-only, disabled by default, and not an acting plugin system.
- OneDrive archive export is policy-gated and unavailable until real encryption is implemented.
- No system control.
- No clipboard access.
- No browser/window automation.
- No external runtime network.
- Redaction is a defense layer, not a complete security boundary.
