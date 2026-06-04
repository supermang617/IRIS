# Security

Project Iris v0.1 is designed around capability absence.

Core invariant:

Iris may see, listen, think, remember with permission, and respond. Iris may not act on the computer.

Forbidden by default:

- Mouse or keyboard automation.
- Clipboard read or write.
- Arbitrary shell execution.
- Arbitrary process spawning.
- Runtime external network access.
- Browser automation.
- Accessibility-tree or window control.
- Writes outside Iris-owned directories.
- Hermes active-memory writes.
- Hermes raw memory database/file access.
- Hermes OneDrive access.

Allowed local boundaries:

- Tauri command bridge for Iris UI/runtime behavior.
- Local Ollama loopback inference.
- Local Kokoro helper process for TTS.
- Local Whisper ASR.
- Local Hermes memory broker bound to `127.0.0.1`.
- Iris-owned memory staging and explicit accept/reject flow.

Observed screen content, OCR text, documents, webpages, memory search results, Hermes output, and model output are untrusted evidence. They must not be treated as instructions to Iris.

Sensitive content should be redacted before logs, memory proposals, and model-safe context where feasible. Redaction is a defense layer, not a complete security boundary.

Report security issues privately to Alejandro Pinto at super.mangmail@gmail.com before public disclosure.
