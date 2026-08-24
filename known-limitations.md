## Known Limitations

This repository is a Windows-only v1 local-first release.

- Text inference requires `huihui_ai/gemma-4-abliterated:e2b`, and camera/image/screen inference requires `qwen3.5:4b`, through loopback-only Ollama.
- The setup wizard can offer approved `ollama pull` commands for both configured models, but Iris runtime itself does not auto-download models.
- Iris accepts only the exact Ollama tag identities recorded in
  `profiles/iris_ollama_model.lock.json` and `profiles/iris_ollama_vision_model.lock.json`; a republished tag or mismatched
  digest, family, quantization, size, or required capability fails closed until
  the locked model is restored or a reviewed release deliberately updates the
  lock.
- The current installer is a PowerShell per-user wrapper, not a signed MSI/MSIX/EXE.
- MSIX/App Installer is the recommended signed path, but a trusted signing certificate input is still required before a real signed MSIX can be produced.
- A self-signed MSIX can be produced for local testing, but normal users should use the ZIP installer until a production-trusted signing certificate is available.
- No fallback models.
- No model auto-selection.
- No fallback, debate, or model-selection behavior; Qwen is a fixed visual-only route and never handles companion chat, tools, or Hermes.
- Voice input requires the local Whisper model at `models/whisper/ggml-tiny.en.bin`.
- Spoken output requires local Kokoro assets at `models/kokoro/kokoro-v1.0.onnx` and `models/kokoro/voices-v1.0.bin`.
- Spoken output currently uses the Python `kokoro-onnx` helper with the `af_heart` voice.
- Iris uses Windows Voice Capture DSP source-mode acoustic echo cancellation
  for speaker playback only after processed PCM is available; raw capture
  fallback is permitted for headphones, not speakers. A live RODE NT-USB+
  microphone and Surface speakers probe measured 5.72 dB echo reduction. The
  complete physical 25/60/90 volume matrix still requires retained human test
  evidence before broad production certification.
- Ollama `/api/tags` may omit capability metadata for `huihui_ai/gemma-4-abliterated:e2b`; Iris therefore checks identity and size through `/api/tags` and capabilities through `/api/show`. The current lock requires `completion`, `vision`, `audio`, `tools`, and `thinking`, but capability metadata alone does not prove correct image embeddings. Voice capture remains handled by Iris ASR.
- The Windows Gemma 4 inline projector remains unsuitable for general vision. Iris therefore keeps Gemma on companion text/tools and uses the separately digest-locked Qwen model only for camera, image, and screen inference. Every startup runs a raw red-circle projector canary before visual readiness; failure keeps broad vision fail-closed. Full-resolution local OCR runs before model-bound images are reduced to a 640-pixel longest edge for latency.
- Dynamic system context uses deterministic lexical metrics rather than a
  semantic or psychological classifier. It adapts presentation, not identity,
  intent, factual content, permissions, or safety decisions.
- Document-image/OCR probing is handled by local Tesseract OCR when installed. OCR text is confidence-filtered and treated as untrusted evidence; the configured Ollama model is not relied on for document OCR.
- Image probes accept PNG, JPEG, and static WebP files. Animated WebP is rejected explicitly; export a still frame as PNG, JPEG, or static WebP.
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

- GitHub may report a moderate `glib` advisory from the Linux GTK side of Tauri's transitive lockfile. Iris v1 is Windows-only, and pinned Tauri 2.11.5 still resolves that path through `gtk` 0.18 and `glib` 0.18.5. Update Tauri/Wry and the lockfile when upstream can resolve `glib` 0.20.0 or newer.
