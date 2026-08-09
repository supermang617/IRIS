## Known Limitations

This repository is a Windows-only v1 local-first release.

- Text inference requires Ollama running locally with `huihui_ai/gemma-4-abliterated:e2b` already available.
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
- Iris now starts interruption monitoring from measured native playback onset
  and can cancel its owned synthesis helper before playback. It does not yet
  implement true acoustic echo cancellation (AEC). Near-field energy gating
  reduces self-triggering but cannot guarantee it on every speaker, room, and
  microphone arrangement; headset use is the most reliable current path.
- Ollama `/api/tags` may omit capability metadata for `huihui_ai/gemma-4-abliterated:e2b`; use `ollama show` or `/api/show` for the authoritative local capability check. The current manual-test machine verifies `completion`, `vision`, `audio`, `tools`, and `thinking` through `/api/show`, but capability metadata alone does not prove correct image embeddings. Voice capture remains handled by Iris ASR.
- The current Windows Ollama Gemma 4 E2B/E4B inline projector path has a known upstream defect. Iris uses confidence-filtered local OCR and a narrow user-selected PNG color/shape classifier for facts it can verify; it refuses unverified general image, camera, and screen scene descriptions instead of guessing. Run `scripts\diagnose_raw_ollama_vision.ps1` after Ollama updates and remove this restriction only after the direct raw-model canary and the wider visual matrix pass.
- Dynamic system context uses deterministic lexical metrics rather than a
  semantic or psychological classifier. It adapts presentation, not identity,
  intent, factual content, permissions, or safety decisions.
- Document-image/OCR probing is handled by local Tesseract OCR when installed. OCR text is confidence-filtered and treated as untrusted evidence; the configured Ollama model is not relied on for document OCR.
- Native Whisper ASR and Kokoro TTS are present.
- Local memory exists, but active-memory promotion is intentionally bounded.
- Safe Hermes is enabled by default for restricted local reasoning, RAG, staged memory proposals, and explicit web research. It is not an acting plugin system.
- Off/Safe/Agentic Session policy, expiry, and the provenance-pinned Hermes Agent 0.18.0 ACP bridge are implemented. Agentic performs supervised local text, file, PowerShell, process, and isolated browser tasks, queries Iris-owned approved memory, and stages memory proposals with provenance.
- Agentic workspace containment is advisory rather than an OS sandbox. Scope-expanding and high-risk actions require separate approval and are recorded in a redacted audit.
- Memory archive export is policy-gated and unavailable until real local encryption is implemented.
- The preflight wizard is read-only. The setup wizard can run allowlisted installs/downloads only when the user explicitly approves them.
- No system control in Safe mode. Agentic control is limited to the reviewed
  file, PowerShell, process, and isolated browser tools.
- No clipboard access.
- Agentic browser automation uses the WinGet-managed Google Chrome engine
  with a dedicated Iris-owned profile. It never opens the user's normal Chrome
  profile. `IRIS_BROWSER_EXECUTABLE_PATH` can select another
  Chromium-compatible executable explicitly.
- Safe mode has no general external network. Agentic browser research and
  recognized Safe primary-source release lookup are the documented exceptions.
- Redaction is a defense layer, not a complete security boundary.

## Dependency Security Notes

- GitHub may report a moderate `glib` advisory from the Linux GTK side of Tauri's transitive lockfile. Iris v1 is Windows-only, and current upstream Tauri 2.11.2 still resolves that path through `gtk` 0.18 and `glib` 0.18.5. Update Tauri/Wry and the lockfile when upstream can resolve `glib` 0.20.0 or newer.
