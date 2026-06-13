## Known Limitations

This repository is a Windows-only v0.1 prototype.

- Text inference requires Ollama running locally with `qwen3.5:9b` already available.
- The setup wizard can offer an approved `ollama pull` for the configured model, but Iris runtime itself does not auto-download or switch models.
- The current installer is a PowerShell per-user wrapper, not a signed MSI/MSIX/EXE.
- MSIX/App Installer is the recommended signed path, but a trusted signing certificate input is still required before a real signed MSIX can be produced.
- A self-signed MSIX can be produced for local testing, but normal users should use the ZIP installer until a production-trusted signing certificate is available.
- No fallback models.
- No model auto-selection.
- No multi-model debate.
- Voice input requires the local Whisper model at `models/whisper/ggml-tiny.en.bin`.
- Spoken output requires local Kokoro assets at `models/kokoro/kokoro-v1.0.onnx` and `models/kokoro/voices-v1.0.bin`.
- Spoken output currently uses the Python `kokoro-onnx` helper with the `af_heart` voice.
- Ollama `/api/tags` may omit vision metadata for `qwen3.5:9b`; use `ollama show` or `/api/show` for the authoritative local capability check. The current manual-test machine verifies `completion`, `vision`, `tools`, and `thinking` through `/api/show`. Audio input remains handled by Iris ASR rather than the language model.
- The configured Ollama model can inspect images, but open-ended geometric shape naming is not fully reliable. Manual release tests use a constrained known-fixture prompt for red-circle validation.
- Document-image/OCR probing is handled by local Tesseract OCR when installed. The current configured Ollama model is not reliable for OCR by itself; direct Ollama calls and Iris image probes failed simple known text fixtures such as `ALPHA 742`, even with deterministic settings and short output caps.
- Native Whisper ASR and Kokoro TTS are present.
- Local memory exists, but active-memory promotion is intentionally bounded.
- Safe Hermes is enabled by default for restricted local reasoning, RAG, staged memory proposals, and explicit web research. It is not an acting plugin system.
- Off/Safe/Agentic Session policy, expiry, and the pinned Hermes Agent 0.16.0 ACP bridge are implemented. Agentic performs supervised local text, file, PowerShell, process, and isolated browser tasks, queries Iris-owned approved memory, and stages memory proposals with provenance.
- Agentic workspace containment is advisory rather than an OS sandbox. Scope-expanding and high-risk actions require separate approval and are recorded in a redacted audit.
- OneDrive archive export is policy-gated and unavailable until real encryption is implemented.
- The preflight wizard is read-only. The setup wizard can run allowlisted installs/downloads only when the user explicitly approves them.
- No system control in Safe mode. Agentic control is limited to the reviewed
  file, PowerShell, process, and isolated browser tools.
- No clipboard access.
- Agentic browser automation uses a dedicated Iris-owned Chrome for Testing
  profile. It does not use the user's normal Chrome or Edge profile.
- Safe mode has no general external network. Agentic browser research and
  recognized Safe primary-source release lookup are the documented exceptions.
- Redaction is a defense layer, not a complete security boundary.

## Dependency Security Notes

- GitHub may report a moderate `glib` advisory from the Linux GTK side of Tauri's transitive lockfile. Iris v0.1 is Windows-only, and current upstream Tauri 2.11.2 still resolves that path through `gtk` 0.18 and `glib` 0.18.5. Update Tauri/Wry and the lockfile when upstream can resolve `glib` 0.20.0 or newer.
