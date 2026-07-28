# Security

Project Iris v1 is designed around deny-by-default capability boundaries.

Core invariant:

Safe-mode Iris may see, listen, think, remember with permission, and respond
without acting on the computer. An explicitly approved, time-limited Agentic
Session may perform only the reviewed local file, PowerShell, process, and
isolated-browser operations, with additional confirmation for high-risk work.

Unavailable in Safe mode:

- Mouse or keyboard automation.
- Clipboard read or write.
- Shell or process execution.
- Runtime external network access.
- Browser automation.
- Accessibility-tree or window control.
- Writes outside Iris-owned directories.
- Hermes active-memory writes.
- Hermes raw memory database/file access.
- Hermes cloud-sync storage access.

Agentic Session does not add mouse, keyboard, clipboard, accessibility-tree, or
general window control. Its selected workspace boundary is advisory rather than
an operating-system sandbox. Scope expansion and high-risk actions require a
separate confirmation, action results are redacted and audited, and Panic Stop
terminates the supervised process tree.

Allowed local boundaries:

- Tauri command bridge for Iris UI/runtime behavior.
- Local Ollama loopback inference.
- Local Kokoro helper process for TTS.
- Local Whisper ASR.
- Local Hermes memory broker bound to `127.0.0.1`.
- Iris-owned memory staging and explicit accept/reject flow.
- Explicitly approved Agentic file, PowerShell, process, and isolated-browser
  work within the reviewed session boundary.

Iris inference and Safe Hermes remain loopback/local-only. The isolated Agentic
browser may access user-requested public HTTP/HTTPS resources, but webpage and
tool content remains untrusted evidence and has no authority to expand tools or
approve actions.

Observed screen content, OCR text, documents, webpages, memory search results, Hermes output, and model output are untrusted evidence. They must not be treated as instructions to Iris.

Sensitive content should be redacted before logs, memory proposals, and model-safe context where feasible. Redaction is a defense layer, not a complete security boundary.

Known dependency alerts are tracked in `known-limitations.md` when they cannot be resolved through the current upstream dependency graph. Do not dismiss a dependency alert without documenting why it is not currently fixable.

Report security issues privately to Alejandro Pinto at super.mangmail@gmail.com before public disclosure.
