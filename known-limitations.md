## Known Limitations

This repository is a slim Windows-only Phase 0 prototype.

- Text inference requires Ollama running locally with `huihui_ai/gemma-4-abliterated:e2b` already available.
- Voice input requires the local Whisper model at `models/whisper/ggml-tiny.en.bin`.
- Spoken output requires local Kokoro assets at `models/kokoro/kokoro-v1.0.onnx` and `models/kokoro/voices-v1.0.bin`.
- Spoken output currently uses the Python `kokoro-onnx` helper with the `af_heart` voice.
- No model downloader.
- No fallback models.
- No screen capture.
- No OCR.
- The configured Ollama model is vision-capable, but Iris has no image-input UI yet.
- Native Whisper ASR and Kokoro TTS are present.
- No persistent memory.
- No system control.
- No clipboard access.
- No plugins.
- Redaction is disabled for direct user text.
