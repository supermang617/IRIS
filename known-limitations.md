## Known Limitations

This repository is a Windows-only v0.1 prototype.

- Text inference requires Ollama running locally with `huihui_ai/gemma-4-abliterated:e2b` already available.
- The setup wizard can offer an approved `ollama pull` for the configured model, but Iris runtime itself does not auto-download or switch models.
- The current installer is a PowerShell per-user wrapper, not a signed MSI/MSIX/EXE.
- MSIX/App Installer is the recommended signed path, but a trusted signing certificate input is still required before a real signed MSIX can be produced.
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
- The preflight wizard is read-only. The setup wizard can run allowlisted installs/downloads only when the user explicitly approves them.
- No system control.
- No clipboard access.
- No browser/window automation.
- No external runtime network.
- Redaction is a defense layer, not a complete security boundary.

## Dependency Security Notes

- GitHub may report a moderate `glib` advisory from the Linux GTK side of Tauri's transitive lockfile. Iris v0.1 is Windows-only, and current upstream Tauri 2.11.2 still resolves that path through `gtk` 0.18 and `glib` 0.18.5. Update Tauri/Wry and the lockfile when upstream can resolve `glib` 0.20.0 or newer.
