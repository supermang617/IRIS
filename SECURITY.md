# Security

Project Iris v0.1 is designed around capability absence.

The core invariant is:

Iris may see, listen, think, remember with permission, and respond. Iris may not act on the computer.

Forbidden in v0.1:

- Mouse or keyboard automation.
- Clipboard read or write.
- Arbitrary shell execution.
- Arbitrary process spawning.
- Runtime external network access.
- HTTP servers.
- Plugin loading.
- Browser automation.
- Accessibility-tree control.
- Writes outside Iris-owned directories.

Observed screen content, OCR text, documents, webpages, and model output are untrusted evidence. They must not be treated as instructions to Iris.

Sensitive content should be redacted before logs, memory proposals, and model-safe context where feasible. Redaction is a defense layer, not a complete security boundary.
